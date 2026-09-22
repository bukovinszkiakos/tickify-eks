using Microsoft.AspNetCore.Identity;

namespace Tickify.Models
{
    public class TicketHistory
    {
        public int Id { get; set; }
        public int TicketId { get; set; }
        public Ticket Ticket { get; set; } = null!;
        public required string ChangedBy { get; set; }
        public IdentityUser ChangedByUser { get; set; } = null!;
        public required string OldStatus { get; set; }
        public required string NewStatus { get; set; }
        public DateTime ChangedAt { get; set; } = DateTime.Now;
    }

}
