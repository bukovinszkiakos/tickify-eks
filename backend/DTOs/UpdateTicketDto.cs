namespace Tickify.DTOs
{
    public class UpdateTicketDto
    {
        public required string Title { get; set; }
        public required string Description { get; set; }
        public required string Status { get; set; }
        public required string Priority { get; set; }
        public string? AssignedTo { get; set; }
    }

}
