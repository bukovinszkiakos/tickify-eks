using Microsoft.AspNetCore.Identity;

namespace Tickify.Models
{
    public class TicketComment
    {
        public int Id { get; set; }
        public int TicketId { get; set; }
        public Ticket Ticket { get; set; }
        public string CommentedBy { get; set; }
        public IdentityUser Commenter { get; set; }
        public string Comment { get; set; }
        public string? ImageUrl { get; set; }  
        public DateTime CreatedAt { get; set; } = DateTime.Now;

        public string CommenterName { get; set; }

    }

}
