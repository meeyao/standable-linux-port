#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_line(const char* msg)
{
    FILE* f = fopen("C:\\stub_log.txt", "a");
    if (f)
    {
        fprintf(f, "[vrpathreg2] %s\n", msg);
        fclose(f);
    }
}

static char* read_file(const char* path)
{
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0) { fclose(f); return NULL; }
    char* buf = (char*)malloc(n + 1);
    size_t r = fread(buf, 1, n, f);
    fclose(f);
    buf[r] = 0;
    return buf;
}

static int write_file(const char* path, const char* content)
{
    FILE* f = fopen(path, "wb");
    if (!f) return 0;
    fwrite(content, 1, strlen(content), f);
    fclose(f);
    return 1;
}

/* Escape a windows path for embedding in JSON: '\\' -> "\\\\", '"' -> "\\\"". */
static size_t json_escape(const char* in, char* out, size_t outsize)
{
    size_t o = 0;
    for (const char* p = in; *p && o + 4 < outsize; p++)
    {
        if (*p == '\\' || *p == '"')
        {
            out[o++] = '\\';
            out[o++] = *p;
        }
        else
        {
            out[o++] = *p;
        }
    }
    out[o] = 0;
    return o;
}

/* Add a driver path to the "external_drivers" array in a vrpath file, if absent. */
static char* add_driver_to_file(const char* path, const char* content)
{
    const char* key = "\"external_drivers\"";
    const char* k = strstr(content, key);
    if (!k) return NULL;
    const char* open = strchr(k, '[');
    if (!open) return NULL;
    const char* close = strchr(open, ']');
    if (!close) return NULL;

    char escaped[4096];
    json_escape(path, escaped, sizeof(escaped));

    /* dedup: look for either the escaped or the raw form */
    if (strstr(content, escaped)) return NULL;
    if (strstr(content, path)) return NULL;

    const char* inner = open + 1;
    const char* inner_end = close;
    while (inner < inner_end && (*inner == ' ' || *inner == '\t' || *inner == '\r' || *inner == '\n'))
        inner++;
    while (inner_end > inner && (*(inner_end - 1) == ' ' || *(inner_end - 1) == '\t' ||
                                 *(inner_end - 1) == '\r' || *(inner_end - 1) == '\n'))
        inner_end--;
    int empty = (inner == inner_end);

    size_t head = (size_t)(open - content) + 1;     /* through '[' */
    size_t mid_len = (size_t)(inner_end - inner);   /* existing entries */
    size_t tail = (size_t)(close - content);        /* from ']' onward */

    size_t alloc = strlen(content) + mid_len + strlen(escaped) + 8;
    char* out = (char*)malloc(alloc);
    size_t o = 0;
    memcpy(out, content, head);
    o = head;
    if (!empty)
    {
        memcpy(out + o, inner, mid_len);
        o += mid_len;
        out[o++] = ',';
    }
    out[o++] = '"';
    o += json_escape(path, out + o, alloc - o);
    out[o++] = '"';
    memcpy(out + o, content + tail, strlen(content) - tail + 1);
    return out;
}

int main(int argc, char** argv)
{
    char cmdline[2048];
    cmdline[0] = 0;
    for (int i = 0; i < argc; i++)
    {
        if (i) strcat(cmdline, " ");
        strncat(cmdline, argv[i], sizeof(cmdline) - strlen(cmdline) - 1);
    }
    log_line(cmdline);

    if (argc >= 3 && strcmp(argv[1], "adddriver") == 0)
    {
        const char* driver = argv[2];
        log_line(driver);

        char local[1024];
        GetEnvironmentVariableA("LOCALAPPDATA", local, sizeof(local));
        if (!local[0]) strcpy(local, "C:\\users\\steamuser\\AppData\\Local");

        const char* files[3];
        char p1[2048], p2[2048], p3[2048];
        snprintf(p1, sizeof(p1), "%s\\openvr\\openvrpaths.vrpath", local);
        files[0] = p1;

        char steam_path[1024];
        DWORD n = sizeof(steam_path);
        LONG rc = RegGetValueA(HKEY_CURRENT_USER, "Software\\Valve\\Steam", "SteamPath",
                               RRF_RT_REG_SZ, NULL, steam_path, &n);
        if (rc == ERROR_SUCCESS && steam_path[0])
        {
            snprintf(p2, sizeof(p2), "%s\\config\\openvrpaths.vrpath", steam_path);
            files[1] = p2;
            snprintf(p3, sizeof(p3), "%s\\steamapps\\common\\SteamVR\\config\\openvrpaths.vrpath", steam_path);
            files[2] = p3;
        }
        else
        {
            files[1] = NULL;
            files[2] = NULL;
        }

        for (int i = 0; i < 3; i++)
        {
            if (!files[i]) continue;
            char* content = read_file(files[i]);
            if (!content) continue;
            char* updated = add_driver_to_file(driver, content);
            if (updated)
            {
                if (write_file(files[i], updated))
                {
                    char buf[4096];
                    snprintf(buf, sizeof(buf), "registered driver in %s", files[i]);
                    log_line(buf);
                }
                free(updated);
            }
            else
            {
                char buf[4096];
                snprintf(buf, sizeof(buf), "already present or no array in %s", files[i]);
                log_line(buf);
            }
            free(content);
        }
    }

    return 0;
}
