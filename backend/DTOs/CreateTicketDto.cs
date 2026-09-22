namespace Tickify.DTOs
{
    public class CreateTicketDto
    {
        public required string Title { get; set; }
        public required string Description { get; set; }
        public string Priority { get; set; } = "Normal";
    }

}
