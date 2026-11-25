using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Interop;
using System.Windows.Threading;

namespace CCLauncher
{
    // パネルのリストに表示する1行分
    public class Item
    {
        public string Group { get; set; }      // 見出し（クリップボード / お気に入り / 最近）
        public int GroupOrder { get; set; }
        public string Name { get; set; }       // フォルダ名（主表示）
        public string Path { get; set; }       // フルパス
        public string DisplayPath { get; set; }// 中央省略したパス
        public string Meta { get; set; }       // 「2時間前」など
        public string Glyph { get; set; }      // 先頭アイコン（Segoe Fluent Icons）
        public bool IsFavorite { get; set; }
        public string Kind { get; set; }       // clipboard / typed / favorite / recent
        public double Score { get; set; }
    }

    public static class Native
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        [DllImport("user32.dll")]
        private static extern bool AllowSetForegroundWindow(int processId);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        // Windows 11 の角丸（DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND）
        public static void SetRoundCorners(IntPtr hwnd) { int v = 2; DwmSetWindowAttribute(hwnd, 33, ref v, 4); }

        public static void SetAppId(string appId) { SetCurrentProcessExplicitAppUserModelID(appId); }
        public static void AllowAnyForeground() { AllowSetForegroundWindow(-1); }
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
        [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hWnd);

        // パネルを確実に前面へ出す（ホットキーやトレイから開いたときに、すぐ文字を打てるように）
        public static bool ForceForeground(IntPtr hwnd)
        {
            if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return true;
            IntPtr fg = GetForegroundWindow();
            uint fgThread = GetWindowThreadProcessId(fg, IntPtr.Zero);
            uint me = GetCurrentThreadId();
            if (fgThread != 0 && fgThread != me)
            {
                AttachThreadInput(me, fgThread, true);
                try { BringWindowToTop(hwnd); SetForegroundWindow(hwnd); }
                finally { AttachThreadInput(me, fgThread, false); }
            }
            return GetForegroundWindow() == hwnd;
        }

        // ---- .lnk に AppUserModelID を書き込む（ジャンプリストとピン留めを結び付けるため） ----
        [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
        private class CShellLink { }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0000010b-0000-0000-C000-000000000046")]
        private interface IPersistFile
        {
            void GetClassID(out Guid pClassID);
            [PreserveSig] int IsDirty();
            void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
            void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
            void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
            void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct PropertyKey
        {
            public Guid fmtid; public uint pid;
            public PropertyKey(Guid g, uint p) { fmtid = g; pid = p; }
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct PropVariant
        {
            [FieldOffset(0)] public ushort vt;
            [FieldOffset(8)] public IntPtr p;
            [FieldOffset(16)] public IntPtr p2; // 64bit で 24 バイトにするための余白
        }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
        private interface IPropertyStore
        {
            void GetCount(out uint cProps);
            void GetAt(uint iProp, out PropertyKey pkey);
            void GetValue(ref PropertyKey key, out PropVariant pv);
            void SetValue(ref PropertyKey key, ref PropVariant pv);
            void Commit();
        }

        public static void SetShortcutAppId(string lnkPath, string appId)
        {
            object link = new CShellLink();
            try
            {
                var pf = (IPersistFile)link;
                pf.Load(lnkPath, 2 /* STGM_READWRITE */);
                var store = (IPropertyStore)link;
                var key = new PropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5); // PKEY_AppUserModel_ID
                var pv = new PropVariant { vt = 31 /* VT_LPWSTR */, p = Marshal.StringToCoTaskMemUni(appId) };
                try { store.SetValue(ref key, ref pv); store.Commit(); }
                finally { Marshal.FreeCoTaskMem(pv.p); }
                pf.Save(lnkPath, true);
            }
            finally { Marshal.ReleaseComObject(link); }
        }
    }

    // グローバルホットキー（メッセージ専用ウィンドウで WM_HOTKEY を受ける）
    public class HotKey : IDisposable
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private const int WM_HOTKEY = 0x0312;
        private const int Id = 0xC1A0;
        private readonly HwndSource _source;
        public bool Registered { get; private set; }
        public event EventHandler Pressed;

        public HotKey(uint modifiers, uint vk)
        {
            var p = new HwndSourceParameters("cc-launcher-hotkey") { ParentWindow = new IntPtr(-3) /* HWND_MESSAGE */, Width = 0, Height = 0, WindowStyle = 0 };
            _source = new HwndSource(p);
            _source.AddHook(WndProc);
            Registered = RegisterHotKey(_source.Handle, Id, modifiers | 0x4000 /* MOD_NOREPEAT */, vk);
        }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY && wParam.ToInt32() == Id)
            {
                handled = true;
                var h = Pressed; if (h != null) h(this, EventArgs.Empty);
            }
            return IntPtr.Zero;
        }

        public void Dispose()
        {
            if (Registered) UnregisterHotKey(_source.Handle, Id);
            _source.Dispose();
        }
    }

    // 別プロセスからの合図（名前付きイベント）を UI スレッドのイベントとして受け取る
    public class Signal
    {
        private readonly EventWaitHandle _handle;
        private readonly Dispatcher _dispatcher;
        public event EventHandler Fired;

        public Signal(string name)
        {
            _handle = new EventWaitHandle(false, EventResetMode.AutoReset, name);
            _dispatcher = Dispatcher.CurrentDispatcher;
            var t = new Thread(Loop) { IsBackground = true, Name = "cc-signal:" + name };
            t.Start();
        }

        private void Loop()
        {
            while (true)
            {
                _handle.WaitOne();
                _dispatcher.BeginInvoke(new Action(() => { var h = Fired; if (h != null) h(this, EventArgs.Empty); }));
            }
        }

        public static bool Send(string name)
        {
            EventWaitHandle h;
            if (!EventWaitHandle.TryOpenExisting(name, out h)) return false;
            using (h) { h.Set(); }
            return true;
        }
    }
}
