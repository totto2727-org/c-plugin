#ifndef CPLUGIN_LIBGIT2_H
#define CPLUGIN_LIBGIT2_H
#include <stddef.h>

/* Opaque operation owns all arguments, output, and libgit2 objects. */
typedef struct cplugin_git_call cplugin_git_call;
enum cplugin_git_operation {
    CPLUGIN_INIT, CPLUGIN_REMOTE_ADD, CPLUGIN_GET_URL, CPLUGIN_FETCH,
    CPLUGIN_REV_PARSE, CPLUGIN_CHECKOUT, CPLUGIN_FSCK, CPLUGIN_CONFIG_URL,
    CPLUGIN_LS_TREE, CPLUGIN_CAT_BLOB, CPLUGIN_HASH_FILES, CPLUGIN_STATUS
};
cplugin_git_call *cplugin_git_new(int operation, int local_test,
    const char *directory, size_t count, const char *const *arguments);
void cplugin_git_cancel(cplugin_git_call *call);
int cplugin_git_run(cplugin_git_call *call);
const char *cplugin_git_output(cplugin_git_call *call, size_t *length);
const char *cplugin_git_error(cplugin_git_call *call);
void cplugin_git_free(cplugin_git_call *call);
#endif
