
namespace RAG_Mbox;

public class MailMessage
{
    public string Subject { get; set; }         = string.Empty;
    public MailAddress From { get; set; }       = new();
    public List<MailAddress> To { get; set; }   = new();
    public List<MailAddress> CC { get; set; }   = new();
    public DateTime Date { get; set; }
    public string Body { get; set; }            = string.Empty;
    public List<MailAttachment> Attachments { get; set; } = new();
}

public class MailAddress
{
    public string DisplayName { get; set; } = string.Empty;
    public string Address { get; set; }     = string.Empty;
}

public class MailAttachment
{
    public string Name { get; set; }    = string.Empty;
    public Stream content { get; set; } = new MemoryStream();
}
