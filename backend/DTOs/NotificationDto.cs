namespace Tickify.DTOs
{
    public class NotificationDto
    {
        public int Id { get; set; }
        public string UserId { get; set; }
        public string Message { get; set; }
        public string? TicketId { get; set; }
        public DateTime CreatedAt { get; set; }
        public bool IsRead { get; set; }
        public bool IsTicketDeleted { get; set; } 
    }
}
