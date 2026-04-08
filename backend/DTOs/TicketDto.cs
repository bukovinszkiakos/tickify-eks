namespace Tickify.DTOs
{
    public class TicketDto
    {
        public int Id { get; set; }
        public string Title { get; set; }
        public string Description { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
        public string Status { get; set; }
        public string Priority { get; set; }
        public string CreatedBy { get; set; }
        public string? AssignedTo { get; set; }
        public string? ImageUrl { get; set; }
        public string? CreatedByName { get; set; }
        public string? AssignedToName { get; set; }
        public int TotalCommentCount { get; set; }
        public int UnreadCommentCount { get; set; } 
    }

}
