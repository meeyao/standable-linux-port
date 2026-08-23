#include <windows.h>
#include <stdio.h>

typedef BOOL(CDECL *VR_INIT_REGISTRY)(void);

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow)
{
    HKEY key;
    HMODULE h;
    VR_INIT_REGISTRY init;
    DWORD state = 0, size, type;
    int i;

    h = LoadLibraryA("C:\\vrclient\\bin\\vrclient_x64.dll");
    if (!h)
    {
        MessageBoxA(NULL, "LoadLibrary(vrclient_x64.dll) failed", "vr-bootstrap", MB_OK);
        return 1;
    }

    init = (VR_INIT_REGISTRY)GetProcAddress(h, "vrclient_init_registry");
    if (!init)
    {
        MessageBoxA(NULL, "GetProcAddress(vrclient_init_registry) failed", "vr-bootstrap", MB_OK);
        return 1;
    }

    init();

    for (i = 0; i < 120; i++)
    {
        Sleep(500);
        if (RegOpenKeyExA(HKEY_CURRENT_USER, "Software\\Wine\\VR", 0, KEY_READ, &key) == ERROR_SUCCESS)
        {
            size = sizeof(state);
            type = 0;
            if (RegQueryValueExA(key, "state", NULL, &type, (BYTE *)&state, &size) == ERROR_SUCCESS)
            {
                RegCloseKey(key);
                if (state == 1 || (int)state == -1)
                    break;
            }
            else
            {
                RegCloseKey(key);
            }
        }
    }

    FreeLibrary(h);
    return 0;
}
