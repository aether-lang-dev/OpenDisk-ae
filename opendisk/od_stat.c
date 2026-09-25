/* od_stat.c — the per-file facts OpenDisk sizes by, which std.fs does not
 * expose: allocated (on-disk) bytes, device id, file id and link count.
 * Split try/get pair like std.fs's stat: od_stat_try(path) fills
 * thread-local fields the getters read. Never follows a symlink.
 *
 * Kinds: 1 file, 2 directory, 3 symlink, 4 other — std.fs's numbering. */
#include <stdint.h>
#include <string.h>

static int     s_kind = 0;
static int64_t s_alloc = 0;
static int64_t s_size = 0;
static int64_t s_dev = 0;
static int64_t s_ino = 0;
static int     s_nlink = 0;

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static int to_wide(const char* p, wchar_t* out, int cap) {
    return MultiByteToWideChar(CP_UTF8, 0, p, -1, out, cap) > 0;
}

int od_stat_try(const char* path) {
    wchar_t w[32768];
    s_kind = 0; s_alloc = 0; s_size = 0; s_dev = 0; s_ino = 0; s_nlink = 0;
    if (!path || !to_wide(path, w, 32768)) return 0;
    WIN32_FILE_ATTRIBUTE_DATA fa;
    if (!GetFileAttributesExW(w, GetFileExInfoStandard, &fa)) return 0;
    if (fa.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) s_kind = 3;
    else if (fa.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) s_kind = 2;
    else s_kind = 1;
    s_size = ((int64_t)fa.nFileSizeHigh << 32) | fa.nFileSizeLow;
    if (s_kind == 1) {
        DWORD hi = 0;
        DWORD lo = GetCompressedFileSizeW(w, &hi);
        if (lo == INVALID_FILE_SIZE && GetLastError() != NO_ERROR) s_alloc = s_size;
        else s_alloc = ((int64_t)hi << 32) | lo;
    }
    HANDLE h = CreateFileW(w, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           NULL, OPEN_EXISTING,
                           FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (h != INVALID_HANDLE_VALUE) {
        BY_HANDLE_FILE_INFORMATION bi;
        if (GetFileInformationByHandle(h, &bi)) {
            s_dev = (int64_t)bi.dwVolumeSerialNumber;
            s_ino = ((int64_t)bi.nFileIndexHigh << 32) | bi.nFileIndexLow;
            s_nlink = (int)bi.nNumberOfLinks;
        }
        CloseHandle(h);
    }
    return 1;
}
#else
#include <sys/types.h>
#include <sys/stat.h>

int od_stat_try(const char* path) {
    struct stat st;
    s_kind = 0; s_alloc = 0; s_size = 0; s_dev = 0; s_ino = 0; s_nlink = 0;
    if (!path || lstat(path, &st) != 0) return 0;
    if (S_ISLNK(st.st_mode)) s_kind = 3;
    else if (S_ISDIR(st.st_mode)) s_kind = 2;
    else if (S_ISREG(st.st_mode)) s_kind = 1;
    else s_kind = 4;
    s_size = (int64_t)st.st_size;
    /* st_blocks is in 512-byte units on every POSIX system we target. */
    s_alloc = (int64_t)st.st_blocks * 512;
    s_dev = (int64_t)st.st_dev;
    s_ino = (int64_t)st.st_ino;
    s_nlink = (int)st.st_nlink;
    return 1;
}
#endif

int     od_stat_kind(void)  { return s_kind; }
int64_t od_stat_alloc(void) { return s_alloc; }
int64_t od_stat_size(void)  { return s_size; }
int64_t od_stat_dev(void)   { return s_dev; }
int64_t od_stat_ino(void)   { return s_ino; }
int     od_stat_nlink(void) { return s_nlink; }
