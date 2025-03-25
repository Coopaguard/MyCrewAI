
using RAG_Mbox;

const string mboxPath = "./Takeout/Mail";
const string exportPath = "./Export";
const string JoinningPath = "./FichiersJoin";


if (!Directory.Exists(mboxPath))
{
    Directory.CreateDirectory(mboxPath);
}
if (!Directory.Exists(exportPath))
{
    Directory.CreateDirectory(exportPath);
}
if (!Directory.Exists(JoinningPath))
{
    Directory.CreateDirectory(JoinningPath);
}

var files = Directory.EnumerateFiles(mboxPath, "*.mbox");
foreach (var mbox in files)
{
    Console.WriteLine($"--- Exporting {mbox} ---");
    var mailMessages = MboxParser.ParserFile(new FileInfo(mbox).FullName);
    foreach (var message in mailMessages)
    {
        ExportMb.SaveExportedMd(message, exportPath, JoinningPath);
    }
}