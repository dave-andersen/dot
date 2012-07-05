#include "async.h"
#include "ftw.h"

int
process_ent(const char *fpath, const struct stat *sb,
            int typeflag, struct FTW *ftwbuf)
{
    warnx("%-50s", fpath);
    switch (typeflag) {
    case FTW_D:
        warnx("DIRECTORY\n");
        break;
    case FTW_SL:
        warnx("SYMLINK\n");
        break;
    case FTW_F:
        warnx("%lu\n", (long unsigned int) sb->st_size);
        break;
    default:
        warnx("???\n");
    }
    return 0;
}

int
main(int argc, char **argv)
{
    int ret;
    vec<char *> paths;

    argv++;
    argc--;

    if (argc <= 0)
        return 0;

    while (argc-- > 0)
        paths.push_back(*argv++);
    paths.push_back(NULL);

    ret = nftw(paths[0], process_ent, 16, FTW_PHYS);
    return ret;
}
