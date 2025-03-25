using MimeKit;
using System.Globalization;
using System.Text;

namespace RAG_Mbox;

public static class MboxParser
{
    public static IEnumerable<MailMessage> ParserFile(string filePath)
    {
        var MailMessages = new List<MailMessage>();
        // Load every message from a Unix mbox
        using (var stream = File.OpenRead(filePath))
        {
            var parser = new MimeParser(stream, MimeFormat.Mbox);
            while (!parser.IsEndOfStream)
            {
                MimeMessage message;
                try
                {
                    message = parser.ParseMessage();
                }
                catch (Exception)
                {
                    Console.WriteLine($"Error while parsing message, skipiing ( file: {filePath} line: {parser.Position})");
                    break;
                }

                var mail = new MailMessage()
                {
                    Subject = message.Subject,
                    To = message.To.Select(x => new MailAddress { DisplayName = x.Name, Address = x.ToString(FormatOptions.Default, false) })?.ToList() ?? [],
                    CC = message.Cc.Select(x => new MailAddress { DisplayName = x.Name, Address = x.ToString(FormatOptions.Default, false) })?.ToList() ?? [],
                    Date = message.Date.Date,
                    Body = message.TextBody
                };

                if(message.From != null && message.From.Count > 0)
                {
                    mail.From = new MailAddress { DisplayName = message.From.First().Name, Address = message.From.First().ToString(FormatOptions.Default, false) };
                }

                foreach(var a in message.Attachments.Where(attach => attach.IsAttachment))
                {
                    if(a is MimeKit.IMimePart attachmentPart)
                    {
                        var attchment = new MailAttachment()
                        {
                            Name = NormalizeString(a.ContentDisposition.FileName)
                        };

                        attachmentPart.Content.DecodeTo(attchment.content);


                        mail.Attachments.Add(attchment);
                    }
                }

                MailMessages.Add(mail);
            }
        }

        return MailMessages;
    }


    private static string NormalizeString(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        var normalizedString = text.Normalize(NormalizationForm.FormD);
        var stringBuilder = new StringBuilder(capacity: normalizedString.Length);

        for (int i = 0; i < normalizedString.Length; i++)
        {
            char c = normalizedString[i];
            var unicodeCategory = CharUnicodeInfo.GetUnicodeCategory(c);
            if (unicodeCategory != UnicodeCategory.NonSpacingMark)
            {
                stringBuilder.Append(c);
            }
        }
        var normalized = stringBuilder
            .ToString()
            .Normalize(NormalizationForm.FormC);

        normalized = Encoding.ASCII.GetString(Encoding.Convert(Encoding.UTF8, Encoding.ASCII, Encoding.UTF8.GetBytes(normalized)));
        normalized = normalized.Replace('/', '_').Replace(':', '-').Replace('?', '_').Replace('*', '_').Replace('|', '_').Replace('<', '_').Replace('>', '_').Replace('"', '_');

        return normalized;
    }
}
