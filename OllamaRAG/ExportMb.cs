
using System.Globalization;
using System.Text;
using System.Web;

namespace RAG_Mbox;

public static class ExportMb
{
    const string mdSource = @"# @subject@

## Headers
De : @sender.name@ <@sender.email@>  
Date: @date@  
Subject: @subject@  
To: @receivers@  
Cc: @cc@

## Attachement
|filename| url |
|---     |---|
@files@

## Body
@body@";

    public static void SaveExportedMd(MailMessage message, string exportPath, string JoinningPath)
    {
        var uniqueId = message.Date.ToString("yyyyMMdd-hhmm") + "_" + Guid.NewGuid().ToString()[..4];

        var md = mdSource.Replace("@subject@", message.Subject);
        md = md.Replace("@sender.name@", message.From.DisplayName);
        md = md.Replace("@sender.email@", message.From.Address);
        md = md.Replace("@date@", message.Date.ToString("dd/MM/yyyy hh:mm"));
        md = md.Replace("@receivers@", string.Join(", ", message.To.Select(t => $"{t.DisplayName} <{t.Address}>")));
        md = md.Replace("@cc@", string.Join(", ", message.CC.Select(t => $"{t.DisplayName} <{t.Address}>")));
        md = md.Replace("@body@", message.Body);

        if (message.Attachments != null && message.Attachments.Count > 0)
        {
            var saveFile = new List<Tuple<string, string>>();
            foreach (var item in message.Attachments)
            {
                var validName = item.Name ?? Guid.NewGuid().ToString();
                var fileName = JoinningPath + "/" + uniqueId + "_" + validName;
                File.WriteAllBytes(fileName, ((MemoryStream)item.content).ToArray());

                saveFile.Add(new Tuple<string, string>(validName, new FileInfo(fileName).FullName));
            }

            if (saveFile.Count > 0)
            {
                md = md.Replace("@files@", string.Join(Environment.NewLine, saveFile.Select(w => $"| {w.Item1} | [{w.Item2}](file:///{HttpUtility.UrlPathEncode(w.Item2)}) |")));
            }
            else
            {
                md = md.Replace("@files@", "");
            }
        }
        else
        {
            md = md.Replace("@files@", "");
        }

        var rows = md.Split(Environment.NewLine).ToList();

        File.WriteAllText($"{exportPath}/{uniqueId}.md", string.Join(Environment.NewLine, rows));
    }

}
