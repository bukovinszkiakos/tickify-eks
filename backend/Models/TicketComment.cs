using Microsoft.AspNetCore.Identity;

namespace Tickify.Models
{
    public class TicketComment
    {
        public int Id { get; set; }
        public int TicketId { get; set; }
        public Ticket Ticket { get; set; } = null!;
        public required string CommentedBy { get; set; }
        public IdentityUser Commenter { get; set; } = null!;
        public required string Comment { get; set; }
        public string? ImageUrl { get; set; }
        public string? OldImageKey { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.Now;

        public required string CommenterName { get; set; }

    }

}
