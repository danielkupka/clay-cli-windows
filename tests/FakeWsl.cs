using System;

// Native process fixture: tests cmd/MSYS boundaries without invoking real WSL.
public static class FakeWsl
{
    public static int Main(string[] args)
    {
        string mode = Environment.GetEnvironmentVariable("CLAY_TEST_WSL_MODE");
        if (mode == "missing")
        {
            Console.Error.WriteLine("WSL is not installed. Test fixture only.");
            return 1;
        }
        if (mode == "distros" || mode == "empty" || mode == "docker")
        {
            if (args.Length != 2 || args[0] != "--list" || args[1] != "--quiet") return 8;
            Console.Error.WriteLine("Test native stderr on a successful invocation.");
            string listing = mode == "distros" ? " Ubuntu-24.04 \n\ndocker-desktop\ndocker-desktop-data\nDebian\n" :
                mode == "docker" ? "docker-desktop\n" : "";
            foreach (char c in listing) { Console.Write(c); Console.Write('\0'); }
            return 0;
        }
        if (mode == "forward")
        {
            Console.WriteLine("MSYS=" + Environment.GetEnvironmentVariable("MSYS_NO_PATHCONV"));
            Console.WriteLine("argc=" + args.Length);
            foreach (string arg in args) Console.WriteLine("arg=" + arg);
            return 23;
        }
        return 9;
    }
}
