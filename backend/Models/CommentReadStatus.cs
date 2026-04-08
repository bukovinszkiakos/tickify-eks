public class CommentReadStatus
{
    public int Id { get; set; }
    public int CommentId { get; set; }
    public string UserId { get; set; } = default!;
    public DateTime SeenAt { get; set; } = DateTime.UtcNow;
}
