public class Notification
{
    public int Id { get; set; }
    public required string UserId { get; set; }
    public required string Message { get; set; }        
    public string? TicketId { get; set; }     
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool IsRead { get; set; } = false;

    public string? CreatedBy { get; set; }  

}
