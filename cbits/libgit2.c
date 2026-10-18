#include "cplugin_libgit2.h"
#include <git2.h>
#include <git2/sys/config.h>
#include <git2/sys/repository.h>
#include <ctype.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if LIBGIT2_VER_MAJOR != 1 || LIBGIT2_VER_MINOR < 9
#error "The experimental backend requires libgit2 >= 1.9"
#endif

struct cplugin_git_call {
    int operation, local_test;
    atomic_int cancelled;
    char *directory, **arguments, *output, *error;
    size_t count, length, capacity;
    git_repository *repo;
    git_odb *odb;
    git_oid *shallow;
    size_t shallow_count;
};

static pthread_mutex_t lifecycle = PTHREAD_MUTEX_INITIALIZER;

static char *copy_string(const char *s)
{
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p) memcpy(p, s, n);
    return p;
}

static int fail(cplugin_git_call *c, const char *message)
{
    if (!c->error) c->error = copy_string(message);
    return -1;
}

static int cancelled(cplugin_git_call *c)
{
    return atomic_load_explicit(&c->cancelled, memory_order_relaxed)
        ? fail(c, "operation cancelled") : 0;
}

static int append(cplugin_git_call *c, const void *bytes, size_t length)
{
    size_t needed;
    char *buffer;
    if (length > SIZE_MAX - c->length - 1) return fail(c, "output too large");
    needed = c->length + length + 1;
    if (needed > c->capacity) {
        size_t capacity = c->capacity ? c->capacity : 256;
        while (capacity < needed) {
            if (capacity > SIZE_MAX / 2) { capacity = needed; break; }
            capacity *= 2;
        }
        buffer = realloc(c->output, capacity);
        if (!buffer) return fail(c, "out of memory");
        c->output = buffer;
        c->capacity = capacity;
    }
    if (length) memcpy(c->output + c->length, bytes, length);
    c->length += length;
    c->output[c->length] = 0;
    return 0;
}

static int text(cplugin_git_call *c, const char *s)
{
    return append(c, s, strlen(s));
}

static int oid_line(cplugin_git_call *c, const git_oid *oid)
{
    char value[GIT_OID_SHA1_HEXSIZE + 2];
    git_oid_tostr(value, sizeof(value), oid);
    value[GIT_OID_SHA1_HEXSIZE] = '\n';
    return append(c, value, GIT_OID_SHA1_HEXSIZE + 1);
}

static char *join_path(const char *directory, const char *path)
{
    size_t a = strlen(directory), b = strlen(path);
    char *result;
    if (path[0] == '/') return copy_string(path);
    if (a > SIZE_MAX - b - 2) return NULL;
    result = malloc(a + b + 2);
    if (result) {
        memcpy(result, directory, a);
        result[a] = '/';
        memcpy(result + a + 1, path, b + 1);
    }
    return result;
}

cplugin_git_call *cplugin_git_new(int operation, int local_test,
    const char *directory, size_t count, const char *const *arguments)
{
    cplugin_git_call *c = calloc(1, sizeof(*c));
    size_t i;
    if (!c) return NULL;
    atomic_init(&c->cancelled, 0);
    c->operation = operation;
    c->local_test = local_test;
    c->count = count;
    c->directory = copy_string(directory);
    c->arguments = calloc(count ? count : 1, sizeof(char *));
    if (!c->directory || !c->arguments) goto error;
    for (i = 0; i < count; i++) {
        c->arguments[i] = copy_string(arguments[i]);
        if (!c->arguments[i]) goto error;
    }
    return c;
error:
    cplugin_git_free(c);
    return NULL;
}

void cplugin_git_cancel(cplugin_git_call *c)
{
    atomic_store_explicit(&c->cancelled, 1, memory_order_relaxed);
}

void cplugin_git_free(cplugin_git_call *c)
{
    size_t i;
    if (!c) return;
    if (c->arguments) for (i = 0; i < c->count; i++) free(c->arguments[i]);
    free(c->arguments);
    free(c->directory);
    free(c->output);
    free(c->error);
    free(c->shallow);
    free(c);
}

const char *cplugin_git_output(cplugin_git_call *c, size_t *length)
{
    *length = c->length;
    return c->output ? c->output : "";
}

const char *cplugin_git_error(cplugin_git_call *c)
{
    return c->error ? c->error : "libgit2 failed";
}

/* Includes could reintroduce external configuration through the local file.
 * Reject them before asking libgit2 to parse any repository-local backend. */
static int reject_config_includes(cplugin_git_call *c, const char *path)
{
    FILE *file = fopen(path, "rb");
    int ch, first = 1, in_section = 0;
    char section[8];
    size_t length = 0;
    if (!file) return fail(c, "cannot read repository configuration");
    while ((ch = fgetc(file)) != EOF) {
        if (ch == '\n') { first = 1; in_section = 0; length = 0; continue; }
        if (first && (ch == ' ' || ch == '\t' || ch == '\r')) continue;
        if (first) { first = 0; if (ch == '[') { in_section = 1; continue; } }
        if (!in_section) continue;
        if (!length && (ch == ' ' || ch == '\t')) continue;
        if (isalpha((unsigned char)ch) && length < sizeof(section) - 1) {
            section[length++] = (char)tolower((unsigned char)ch);
            section[length] = 0;
            if (length == 7 && !strcmp(section, "include")) {
                fclose(file);
                return fail(c, "repository configuration includes are forbidden");
            }
        } else in_section = 0;
    }
    ch = ferror(file);
    fclose(file);
    return ch ? fail(c, "cannot read repository configuration") : 0;
}

/* libgit2 1.9 declares its memory constructors without exporting them. This
 * immutable backend uses only the exported custom-backend ABI instead. */
static const struct { const char *name, *value; } safety_values[] = {
    { "core.hookspath", "/dev/null" }, { "core.fsmonitor", "false" },
    { "core.attributesfile", "/dev/null" }, { "core.filemode", "true" },
    { "core.ignorecase", "false" }, { "core.quotepath", "true" },
    { "submodule.recurse", "false" }, { "fetch.recursesubmodules", "false" },
    { "http.followredirects", "false" }, { "credential.interactive", "false" }
};

static void safety_entry_free(git_config_backend_entry *entry) { free(entry); }

static void safety_entry(git_config_backend_entry *entry, size_t index)
{
    memset(entry, 0, sizeof(*entry));
    entry->entry.name = safety_values[index].name;
    entry->entry.value = safety_values[index].value;
    entry->entry.backend_type = "c-plugin safety";
    entry->entry.level = GIT_CONFIG_LEVEL_APP;
}

static int safety_open(git_config_backend *backend, git_config_level_t level,
    const git_repository *repo)
{
    (void)backend; (void)level; (void)repo;
    return 0;
}

static int safety_get(git_config_backend *backend, const char *key,
    git_config_backend_entry **out)
{
    size_t i;
    (void)backend;
    *out = NULL;
    for (i = 0; i < sizeof(safety_values) / sizeof(safety_values[0]); i++) {
        git_config_backend_entry *entry;
        if (strcmp(key, safety_values[i].name)) continue;
        entry = malloc(sizeof(*entry));
        if (!entry) return -1;
        safety_entry(entry, i);
        entry->free = safety_entry_free;
        *out = entry;
        return 0;
    }
    return GIT_ENOTFOUND;
}

typedef struct {
    git_config_iterator parent;
    size_t position;
} safety_iterator;

static int safety_next(git_config_backend_entry **out, git_config_iterator *parent)
{
    safety_iterator *iterator = (safety_iterator *)parent;
    *out = NULL;
    if (iterator->position == sizeof(safety_values) / sizeof(safety_values[0])) return GIT_ITEROVER;
    return safety_get(parent->backend, safety_values[iterator->position++].name, out);
}

static void safety_iterator_free(git_config_iterator *iterator) { free(iterator); }

static int safety_iterate(git_config_iterator **out, git_config_backend *backend)
{
    safety_iterator *iterator = calloc(1, sizeof(*iterator));
    if (!iterator) return -1;
    iterator->parent.backend = backend;
    iterator->parent.next = safety_next;
    iterator->parent.free = safety_iterator_free;
    *out = &iterator->parent;
    return 0;
}

static int safety_backend(git_config_backend **out);
static int safety_snapshot(git_config_backend **out, git_config_backend *backend)
{
    (void)backend;
    return safety_backend(out);
}

static void safety_free(git_config_backend *backend) { free(backend); }

static int safety_backend(git_config_backend **out)
{
    git_config_backend *backend = calloc(1, sizeof(*backend));
    if (!backend) return -1;
    backend->version = GIT_CONFIG_BACKEND_VERSION;
    backend->readonly = 1;
    backend->open = safety_open;
    backend->get = safety_get;
    backend->iterator = safety_iterate;
    backend->snapshot = safety_snapshot;
    backend->free = safety_free;
    *out = backend;
    return 0;
}

/* No global/system/XDG config or environment mutation. The memory overlay is
 * read-only, so remote creation writes only the repository-local backend. */
static int isolate_config(cplugin_git_call *c)
{
    git_config_level_t write_level = GIT_CONFIG_LEVEL_LOCAL;
    git_config *config = NULL;
    git_config_backend *overlay = NULL;
    char *path = join_path(git_repository_path(c->repo), "config");
    int result = -1;
    if (!path) return fail(c, "out of memory");
    if (reject_config_includes(c, path) < 0) goto done;
    if (git_config_new(&config) < 0) goto done;
    if (git_config_add_file_ondisk(config, path, GIT_CONFIG_LEVEL_LOCAL, NULL, 0) < 0) goto done;
    if (safety_backend(&overlay) < 0) goto done;
    if (git_config_add_backend(config, overlay, GIT_CONFIG_LEVEL_APP, NULL, 0) < 0) goto done;
    overlay = NULL;
    if (git_config_set_writeorder(config, &write_level, 1) < 0) goto done;
    result = git_repository_set_config(c->repo, config);
done:
    if (overlay) overlay->free(overlay);
    git_config_free(config);
    free(path);
    return result;
}

static int progress(const git_indexer_progress *stats, void *payload)
{
    (void)stats;
    return cancelled(payload);
}

static int sideband(const char *data, int length, void *payload)
{
    (void)data;
    (void)length;
    return cancelled(payload);
}

static int checkout_notify(git_checkout_notify_t why, const char *path,
    const git_diff_file *baseline, const git_diff_file *target,
    const git_diff_file *workdir, void *payload)
{
    (void)why; (void)path; (void)baseline; (void)target; (void)workdir;
    return cancelled(payload);
}

static int fetch(cplugin_git_call *c)
{
    git_remote *remote = NULL;
    git_fetch_options options = GIT_FETCH_OPTIONS_INIT;
    git_remote_create_options create = GIT_REMOTE_CREATE_OPTIONS_INIT;
    git_strarray refs = { c->arguments + 1, 1 };
    int result;
    const char *url = c->arguments[0];
    if (strncmp(url, "https://github.com/", 19) != 0 &&
        !(c->local_test && url[0] == '/' && url[1] != '/'))
        return fail(c, "disallowed fetch endpoint");
    create.repository = c->repo;
    create.flags = GIT_REMOTE_CREATE_SKIP_INSTEADOF | GIT_REMOTE_CREATE_SKIP_DEFAULT_FETCHSPEC;
    if (git_remote_create_with_opts(&remote, url, &create) < 0) return -1;
    /* libgit2's local transport cannot negotiate shallow fetches. Only the
     * separately named fixture seam uses a full local object transfer. */
    options.depth = (c->local_test && url[0] == '/') ? 0 : 1;
    options.download_tags = GIT_REMOTE_DOWNLOAD_TAGS_NONE;
    options.update_fetchhead = 1;
    options.follow_redirects = GIT_REMOTE_REDIRECT_NONE;
    options.proxy_opts.type = GIT_PROXY_NONE;
    options.callbacks.transfer_progress = progress;
    options.callbacks.sideband_progress = sideband;
    options.callbacks.payload = c;
    /* No credential helper, certificate override, remote URL resolver, or
     * submodule operation is installed. libgit2 never invokes Git hooks. */
    result = git_remote_fetch(remote, &refs, &options, NULL);
    git_remote_free(remote);
    return result;
}

static int resolve(cplugin_git_call *c, const char *revision, git_object_t type, git_object **out)
{
    git_object *object = NULL;
    int result;
    if (git_revparse_single(&object, c->repo, revision) < 0) return -1;
    result = git_object_peel(out, object, type);
    git_object_free(object);
    return result;
}

static int tree_entry(const char *root, const git_tree_entry *entry, void *payload)
{
    cplugin_git_call *c = payload;
    char header[96], oid[GIT_OID_SHA1_HEXSIZE + 1];
    git_object_t type = git_tree_entry_type(entry);
    int length;
    if (cancelled(c) < 0) return -1;
    if (type == GIT_OBJECT_TREE) return 0;
    git_oid_tostr(oid, sizeof(oid), git_tree_entry_id(entry));
    length = snprintf(header, sizeof(header), "%06o %s %s\t",
        (unsigned int)git_tree_entry_filemode_raw(entry), git_object_type2string(type), oid);
    if (length < 0 || (size_t)length >= sizeof(header)) return fail(c, "invalid tree entry");
    if (append(c, header, (size_t)length) < 0 || text(c, root) < 0 ||
        text(c, git_tree_entry_name(entry)) < 0 || append(c, "", 1) < 0) return -1;
    return 0;
}

/* Hash every object, including unreachable ones. Then parse each object's
 * references and require their types and existence. Only parents of explicitly
 * recorded shallow boundary commits may be absent. */
static int require_object(cplugin_git_call *c, const git_oid *id, git_object_t type)
{
    git_object *object = NULL;
    git_odb_object *raw = NULL;
    git_oid actual;
    int result = -1;
    if (git_odb_read(&raw, c->odb, id) < 0) goto done;
    if (git_odb_hash(&actual, git_odb_object_data(raw), git_odb_object_size(raw),
            git_odb_object_type(raw)) < 0) goto done;
    if (!git_oid_equal(&actual, id)) { fail(c, "referenced object content does not match its ID"); goto done; }
    result = git_object_lookup(&object, c->repo, id, type);
done:
    git_odb_object_free(raw);
    git_object_free(object);
    return result;
}

static int shallow_boundary(cplugin_git_call *c, const git_oid *id)
{
    size_t i;
    for (i = 0; i < c->shallow_count; i++) if (git_oid_equal(id, c->shallow + i)) return 1;
    return 0;
}

static int check_object(const git_oid *id, void *payload)
{
    cplugin_git_call *c = payload;
    git_odb_object *raw = NULL;
    git_object *object = NULL;
    git_oid actual;
    git_object_t type;
    size_t i;
    int result = -1;
    if (cancelled(c) < 0 || git_odb_read(&raw, c->odb, id) < 0) goto done;
    type = git_odb_object_type(raw);
    if (git_odb_hash(&actual, git_odb_object_data(raw), git_odb_object_size(raw), type) < 0) goto done;
    if (!git_oid_equal(&actual, id)) { fail(c, "object content does not match its ID"); goto done; }
    if (git_object_lookup(&object, c->repo, id, type) < 0) goto done;
    switch (type) {
    case GIT_OBJECT_COMMIT: {
        git_commit *commit = (git_commit *)object;
        if (require_object(c, git_commit_tree_id(commit), GIT_OBJECT_TREE) < 0) goto done;
        if (!shallow_boundary(c, id)) {
            for (i = 0; i < git_commit_parentcount(commit); i++)
                if (require_object(c, git_commit_parent_id(commit, (unsigned int)i), GIT_OBJECT_COMMIT) < 0) goto done;
        }
        break;
    }
    case GIT_OBJECT_TREE: {
        git_tree *tree = (git_tree *)object;
        for (i = 0; i < git_tree_entrycount(tree); i++) {
            const git_tree_entry *entry = git_tree_entry_byindex(tree, i);
            git_filemode_t mode = git_tree_entry_filemode_raw(entry);
            if (mode == GIT_FILEMODE_COMMIT) continue;
            if (mode != GIT_FILEMODE_TREE && mode != GIT_FILEMODE_BLOB &&
                mode != GIT_FILEMODE_BLOB_EXECUTABLE && mode != GIT_FILEMODE_LINK) {
                fail(c, "invalid tree file mode"); goto done;
            }
            if (require_object(c, git_tree_entry_id(entry), git_tree_entry_type(entry)) < 0) goto done;
        }
        break;
    }
    case GIT_OBJECT_TAG:
        if (require_object(c, git_tag_target_id((git_tag *)object),
                git_tag_target_type((git_tag *)object)) < 0) goto done;
        break;
    case GIT_OBJECT_BLOB: break;
    default: fail(c, "invalid object type"); goto done;
    }
    result = 0;
done:
    git_object_free(object);
    git_odb_object_free(raw);
    return result;
}

static int read_shallow(cplugin_git_call *c)
{
    char *path = join_path(git_repository_path(c->repo), "shallow");
    FILE *file;
    char line[GIT_OID_SHA1_HEXSIZE + 3];
    int result = -1;
    if (!path) return fail(c, "out of memory");
    file = fopen(path, "rb");
    if (!file) {
        int missing = errno == ENOENT;
        free(path);
        return missing ? 0 : fail(c, "cannot read shallow boundaries");
    }
    free(path);
    while (fgets(line, sizeof(line), file)) {
        git_oid id, *ids;
        size_t n = strlen(line);
        if (n != GIT_OID_SHA1_HEXSIZE + 1 || line[GIT_OID_SHA1_HEXSIZE] != '\n' ||
            git_oid_fromstrn(&id, line, GIT_OID_SHA1_HEXSIZE) < 0) goto done;
        if (c->shallow_count == SIZE_MAX / sizeof(git_oid)) goto done;
        ids = realloc(c->shallow, (c->shallow_count + 1) * sizeof(git_oid));
        if (!ids) goto done;
        c->shallow = ids;
        c->shallow[c->shallow_count++] = id;
        if (require_object(c, &id, GIT_OBJECT_COMMIT) < 0) goto done;
    }
    if (ferror(file)) goto done;
    result = 0;
done:
    fclose(file);
    return result < 0 ? fail(c, "invalid shallow boundaries") : 0;
}

static int fsck(cplugin_git_call *c)
{
    git_reference_iterator *iterator = NULL;
    git_reference *reference = NULL, *resolved = NULL;
    git_object *head = NULL;
    git_index *index = NULL;
    size_t i;
    int result = -1, next;
    if (git_repository_odb(&c->odb, c->repo) < 0 || read_shallow(c) < 0) goto done;
    if (git_odb_foreach(c->odb, check_object, c) < 0) goto done;
    if (resolve(c, "HEAD", GIT_OBJECT_COMMIT, &head) < 0 ||
        require_object(c, git_object_id(head), GIT_OBJECT_COMMIT) < 0) goto done;
    if (git_reference_iterator_new(&iterator, c->repo) < 0) goto done;
    while ((next = git_reference_next(&reference, iterator)) == 0) {
        if (cancelled(c) < 0 || git_reference_resolve(&resolved, reference) < 0) goto done;
        if (require_object(c, git_reference_target(resolved), GIT_OBJECT_ANY) < 0) goto done;
        git_reference_free(reference); reference = NULL;
        git_reference_free(resolved); resolved = NULL;
    }
    if (next != GIT_ITEROVER) goto done;
    if (git_repository_index(&index, c->repo) < 0) goto done;
    for (i = 0; i < git_index_entrycount(index); i++) {
        const git_index_entry *entry = git_index_get_byindex(index, i);
        if (cancelled(c) < 0) goto done;
        if (entry->mode == GIT_FILEMODE_COMMIT) continue;
        if (require_object(c, &entry->id, GIT_OBJECT_BLOB) < 0) goto done;
    }
    result = 0;
done:
    git_index_free(index);
    git_object_free(head);
    git_reference_free(reference);
    git_reference_free(resolved);
    git_reference_iterator_free(iterator);
    return result;
}

static int quote_path(cplugin_git_call *c, const char *path)
{
    const unsigned char *p = (const unsigned char *)path;
    int quoted = 0;
    for (; *p; p++) if (*p < 32 || *p >= 127 || *p == '"' || *p == '\\') quoted = 1;
    if (!quoted) return text(c, path);
    if (text(c, "\"") < 0) return -1;
    for (p = (const unsigned char *)path; *p; p++) {
        char escaped[5];
        const char *special = NULL;
        switch (*p) {
        case '\a': special = "\\a"; break;
        case '\b': special = "\\b"; break;
        case '\t': special = "\\t"; break;
        case '\n': special = "\\n"; break;
        case '\v': special = "\\v"; break;
        case '\f': special = "\\f"; break;
        case '\r': special = "\\r"; break;
        case '"': special = "\\\""; break;
        case '\\': special = "\\\\"; break;
        default: break;
        }
        if (special) { if (text(c, special) < 0) return -1; }
        else if (*p < 32 || *p >= 127) {
            snprintf(escaped, sizeof(escaped), "\\%03o", *p);
            if (text(c, escaped) < 0) return -1;
        } else if (append(c, p, 1) < 0) return -1;
    }
    return text(c, "\"");
}

static int status(cplugin_git_call *c)
{
    git_status_options options = GIT_STATUS_OPTIONS_INIT;
    git_status_list *list = NULL;
    size_t i;
    int result = -1, group;
    options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    options.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED | GIT_STATUS_OPT_INCLUDE_IGNORED |
        GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS | GIT_STATUS_OPT_RECURSE_IGNORED_DIRS |
        GIT_STATUS_OPT_SORT_CASE_SENSITIVELY | GIT_STATUS_OPT_INCLUDE_UNREADABLE |
        GIT_STATUS_OPT_EXCLUDE_SUBMODULES | GIT_STATUS_OPT_NO_REFRESH |
        GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX;
    if (git_status_list_new(&list, c->repo, &options) < 0) return -1;
    /* Porcelain emits tracked changes, then untracked, then ignored paths. */
    for (group = 0; group < 3; group++) {
    for (i = 0; i < git_status_list_entrycount(list); i++) {
        const git_status_entry *entry = git_status_byindex(list, i);
        unsigned int s = entry->status;
        char xy[3] = { ' ', ' ', ' ' };
        const char *path;
        if (cancelled(c) < 0) goto done;
        if (s == GIT_STATUS_CURRENT) continue;
        if ((s & GIT_STATUS_IGNORED ? 2 : s & GIT_STATUS_WT_NEW ? 1 : 0) != group) continue;
        if (s & GIT_STATUS_INDEX_NEW) xy[0] = 'A';
        if (s & GIT_STATUS_INDEX_MODIFIED) xy[0] = 'M';
        if (s & GIT_STATUS_INDEX_DELETED) xy[0] = 'D';
        if (s & GIT_STATUS_INDEX_TYPECHANGE) xy[0] = 'T';
        if (s & GIT_STATUS_INDEX_RENAMED) xy[0] = 'R';
        if (s & GIT_STATUS_WT_MODIFIED) xy[1] = 'M';
        if (s & GIT_STATUS_WT_DELETED) xy[1] = 'D';
        if (s & GIT_STATUS_WT_TYPECHANGE) xy[1] = 'T';
        if (s & GIT_STATUS_WT_UNREADABLE) xy[1] = 'M';
        if (s & GIT_STATUS_WT_NEW) xy[0] = xy[1] = '?';
        if (s & GIT_STATUS_IGNORED) xy[0] = xy[1] = '!';
        if (s & GIT_STATUS_CONFLICTED) { fail(c, "conflicted cache index"); goto done; }
        path = entry->index_to_workdir ? entry->index_to_workdir->new_file.path : entry->head_to_index->new_file.path;
        if (append(c, xy, 3) < 0) goto done;
        if (s & GIT_STATUS_INDEX_RENAMED) {
            if (quote_path(c, entry->head_to_index->old_file.path) < 0 || text(c, " -> ") < 0) goto done;
        }
        if (quote_path(c, path) < 0 || text(c, "\n") < 0) goto done;
    }
    }
    result = 0;
done:
    git_status_list_free(list);
    return result;
}

static int dispatch(cplugin_git_call *c)
{
    git_object *object = NULL;
    git_remote *remote = NULL;
    git_config *config = NULL;
    git_buf value = GIT_BUF_INIT;
    git_oid oid;
    char *path = NULL;
    size_t i;
    int result = -1;
    if (cancelled(c) < 0) return -1;
    if (c->operation == CPLUGIN_GET_URL) {
        if (text(c, c->arguments[0]) < 0) return -1;
        return text(c, "\n");
    }
    if (c->operation == CPLUGIN_INIT) {
        git_repository_init_options options = GIT_REPOSITORY_INIT_OPTIONS_INIT;
        options.flags = GIT_REPOSITORY_INIT_MKPATH | GIT_REPOSITORY_INIT_NO_REINIT;
        options.initial_head = "refs/heads/master";
        path = join_path(c->directory, c->arguments[0]);
        if (!path) return fail(c, "out of memory");
        if (git_repository_init_ext(&c->repo, path, &options) < 0) goto done;
        if (text(c, "Initialized empty Git repository in ") < 0 ||
            text(c, git_repository_path(c->repo)) < 0 || text(c, "\n") < 0) goto done;
        result = 0;
        goto done;
    }
    path = join_path(c->directory, ".git");
    if (!path) return fail(c, "out of memory");
    /* Bare opening defers config loading. Install isolated config before
     * selecting an explicit workdir, so global core.worktree cannot redirect it. */
    if (git_repository_open_ext(&c->repo, path, GIT_REPOSITORY_OPEN_NO_SEARCH |
            GIT_REPOSITORY_OPEN_NO_DOTGIT | GIT_REPOSITORY_OPEN_BARE, NULL) < 0) goto done;
    free(path); path = NULL;
    if (isolate_config(c) < 0 || git_repository_set_workdir(c->repo, c->directory, 0) < 0) goto done;
    switch (c->operation) {
    case CPLUGIN_REMOTE_ADD: {
        git_remote_create_options options = GIT_REMOTE_CREATE_OPTIONS_INIT;
        options.repository = c->repo;
        options.name = "origin";
        options.flags = GIT_REMOTE_CREATE_SKIP_INSTEADOF;
        result = git_remote_create_with_opts(&remote, c->arguments[0], &options);
        break;
    }
    case CPLUGIN_FETCH:
        result = fetch(c);
        break;
    case CPLUGIN_REV_PARSE:
        if (resolve(c, c->arguments[0], GIT_OBJECT_COMMIT, &object) < 0) break;
        result = oid_line(c, git_object_id(object));
        break;
    case CPLUGIN_CHECKOUT: {
        git_checkout_options options = GIT_CHECKOUT_OPTIONS_INIT;
        if (resolve(c, c->arguments[0], GIT_OBJECT_COMMIT, &object) < 0) break;
        options.checkout_strategy = GIT_CHECKOUT_SAFE | GIT_CHECKOUT_RECREATE_MISSING;
        options.disable_filters = 1;
        options.notify_flags = GIT_CHECKOUT_NOTIFY_ALL;
        options.notify_cb = checkout_notify;
        options.notify_payload = c;
        if (git_checkout_tree(c->repo, object, &options) < 0) break;
        result = git_repository_set_head_detached(c->repo, git_object_id(object));
        break;
    }
    case CPLUGIN_FSCK:
        result = fsck(c);
        break;
    case CPLUGIN_CONFIG_URL:
        if (git_repository_config(&config, c->repo) < 0 ||
            git_config_get_string_buf(&value, config, "remote.origin.url") < 0) break;
        if (append(c, value.ptr, value.size) < 0) break;
        result = text(c, "\n");
        break;
    case CPLUGIN_LS_TREE:
        if (resolve(c, c->arguments[0], GIT_OBJECT_TREE, &object) < 0) break;
        result = git_tree_walk((git_tree *)object, GIT_TREEWALK_PRE, tree_entry, c);
        break;
    case CPLUGIN_CAT_BLOB:
        if (git_oid_fromstr(&oid, c->arguments[0]) < 0 ||
            git_object_lookup(&object, c->repo, &oid, GIT_OBJECT_BLOB) < 0) break;
        result = append(c, git_blob_rawcontent((git_blob *)object), git_blob_rawsize((git_blob *)object));
        break;
    case CPLUGIN_HASH_FILES:
        result = 0;
        for (i = 0; i < c->count; i++) {
            if (cancelled(c) < 0) { result = -1; break; }
            path = join_path(c->directory, c->arguments[i]);
            if (!path) { result = fail(c, "out of memory"); break; }
            result = git_odb_hashfile(&oid, path, GIT_OBJECT_BLOB);
            free(path); path = NULL;
            if (result < 0 || (result = oid_line(c, &oid)) < 0) break;
        }
        break;
    case CPLUGIN_STATUS:
        result = status(c);
        break;
    default:
        result = fail(c, "unsupported internal operation");
        break;
    }
done:
    free(path);
    git_buf_dispose(&value);
    git_config_free(config);
    git_remote_free(remote);
    git_object_free(object);
    return result;
}

int cplugin_git_run(cplugin_git_call *c)
{
    int initialized, result;
    const git_error *error;
    pthread_mutex_lock(&lifecycle);
    initialized = git_libgit2_init();
    pthread_mutex_unlock(&lifecycle);
    if (initialized < 0) return fail(c, "could not initialize libgit2");
    result = dispatch(c);
    if (result < 0 && !c->error) {
        error = git_error_last();
        fail(c, error && error->message ? error->message : "libgit2 failed");
    }
    git_odb_free(c->odb); c->odb = NULL;
    git_repository_free(c->repo); c->repo = NULL;
    pthread_mutex_lock(&lifecycle);
    git_libgit2_shutdown();
    pthread_mutex_unlock(&lifecycle);
    return result;
}
