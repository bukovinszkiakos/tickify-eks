namespace Tickify.DTOs
{
    public class TicketDto
    {
        public int Id { get; set; }
        public required string Title { get; set; }
        public required string Description { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
        public required string Status { get; set; }
        public required string Priority { get; set; }
        public required string CreatedBy { get; set; }
        public string? AssignedTo { get; set; }
        public string? ImageUrl { get; set; }
        public string? CreatedByName { get; set; }
        public string? AssignedToName { get; set; }
        public int TotalCommentCount { get; set; }
        public int UnreadCommentCount { get; set; } 
    }

}
