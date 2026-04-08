using Microsoft.AspNetCore.Identity;

namespace Tickify.Models
{
    public class TicketHistory
    {
        public int Id { get; set; }
        public int TicketId { get; set; }
        public Ticket Ticket { get; set; }
        public string ChangedBy { get; set; }
        public IdentityUser ChangedByUser { get; set; }
        public string OldStatus { get; set; }
        public string NewStatus { get; set; }
        public DateTime ChangedAt { get; set; } = DateTime.Now;
    }

}
