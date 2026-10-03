using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

// A suspended launch closes the race between creating children and assigning ownership.
// The non-inheritable job handle also cleans up descendants if the driver itself dies.
public sealed class SweatshopStageProcess : IDisposable
{
    IntPtr job, process;
    public int Id { get; private set; }
    [StructLayout(LayoutKind.Sequential)] struct Security { public int Length; public IntPtr Descriptor; public int Inherit; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct Startup {
        public int Size; public string Reserved, Desktop, Title;
        public int X, Y, XSize, YSize, XChars, YChars, Fill, Flags;
        public short Show, ReservedSize; public IntPtr ReservedBytes, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr Process, Thread; public int Id, ThreadId; }
    [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
        public long ProcessTime, JobTime; public uint Flags; public UIntPtr Min, Max;
        public uint Active; public UIntPtr Affinity; public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] struct Limits { public BasicLimits Basic; public IoCounters Io; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
    [StructLayout(LayoutKind.Sequential)] struct Accounting {
        public long User, Kernel, PeriodUser, PeriodKernel;
        public uint Faults, Total, Active, Terminated;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref Limits limits, int size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CreateProcess(string app, StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref Startup startup, out ProcessInfo info);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateFile(string name, uint access, uint share, ref Security security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr process, uint exit);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr job, uint exit);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, out Accounting info, int size, IntPtr returned);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint ms);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    static void Check(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    static IntPtr Open(string path, uint access, uint disposition, ref Security security) {
        var handle = CreateFile(path, access, 7, ref security, disposition, 0x80, IntPtr.Zero);
        if (handle == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        return handle;
    }
    public static SweatshopStageProcess Start(string exe, string args, string cwd, string log) {
        var owner = new SweatshopStageProcess();
        var info = new ProcessInfo();
        IntPtr input = IntPtr.Zero, output = IntPtr.Zero, error = IntPtr.Zero;
        try {
            owner.job = CreateJobObject(IntPtr.Zero, null);
            Check(owner.job != IntPtr.Zero);
            var limits = new Limits(); limits.Basic.Flags = 0x2000; // KILL_ON_JOB_CLOSE; no breakaway
            Check(SetInformationJobObject(owner.job, 9, ref limits, Marshal.SizeOf(typeof(Limits))));
            var security = new Security { Length = Marshal.SizeOf(typeof(Security)), Inherit = 1 };
            input = Open("NUL", 0x80000000, 3, ref security);
            output = Open(log, 0x40000000, 2, ref security);
            error = Open(log + ".err", 0x40000000, 2, ref security);
            var startup = new Startup { Size = Marshal.SizeOf(typeof(Startup)), Flags = 0x100, Input = input, Output = output, Error = error };
            string command = "\"" + exe + "\" " + args;
            if (exe.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || exe.EndsWith(".bat", StringComparison.OrdinalIgnoreCase)) {
                command = "\"" + Environment.GetEnvironmentVariable("ComSpec") + "\" /d /s /c \"" + command + "\"";
                exe = Environment.GetEnvironmentVariable("ComSpec");
            }
            Check(CreateProcess(exe, new StringBuilder(command), IntPtr.Zero, IntPtr.Zero, true,
                0x08000004, IntPtr.Zero, cwd, ref startup, out info)); // NO_WINDOW | SUSPENDED
            owner.process = info.Process; owner.Id = info.Id;
            Check(AssignProcessToJobObject(owner.job, owner.process));
            Check(ResumeThread(info.Thread) != UInt32.MaxValue);
            return owner;
        } catch {
            if (info.Process != IntPtr.Zero) TerminateProcess(info.Process, 1);
            owner.Dispose(); throw;
        } finally {
            foreach (var handle in new[] { input, output, error, info.Thread }) if (handle != IntPtr.Zero) CloseHandle(handle);
        }
    }
    public bool HasExited { get {
        uint result = WaitForSingleObject(process, 0);
        if (result == UInt32.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
        return result == 0;
    } }
    public int ExitCode { get { uint code; Check(GetExitCodeProcess(process, out code)); return unchecked((int)code); } }
    public void Stop() {
        Check(TerminateJobObject(job, 1));
        var wait = System.Diagnostics.Stopwatch.StartNew();
        do {
            Accounting info;
            Check(QueryInformationJobObject(job, 1, out info, Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero));
            if (info.Active == 0) return;
            System.Threading.Thread.Sleep(20);
        } while (wait.ElapsedMilliseconds < 5000);
        throw new InvalidOperationException("Stage job still has active processes after 5 seconds.");
    }
    public void Dispose() {
        if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; }
        if (process != IntPtr.Zero) { CloseHandle(process); process = IntPtr.Zero; }
    }
}
