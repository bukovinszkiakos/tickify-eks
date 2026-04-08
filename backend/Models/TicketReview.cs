using Microsoft.AspNetCore.Identity;

namespace Tickify.Models
{
    public class TicketReview
    {
        public int Id { get; set; }
        public int TicketId { get; set; }
        public Ticket Ticket { get; set; }
        public string ReviewedBy { get; set; }
        public IdentityUser Reviewer { get; set; }
        public string Review { get; set; }
        public int Rating { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }

}
