namespace ASCIIKoiPond;

internal static class Log
{
    public static string FilePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ASCIIKoiPond", "error.log");

    public static void Error(Exception? ex) => Write("ERROR " + ex);

    public static void Write(string msg)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.AppendAllText(FilePath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {msg}{Environment.NewLine}");
        }
        catch { }
    }
}
