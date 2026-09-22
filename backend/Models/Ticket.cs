using Microsoft.AspNetCore.Identity;
using Tickify.Models;

public class Ticket
{
    public int Id { get; set; }
    public required string Title { get; set; }
    public required string Description { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.Now;
    public DateTime UpdatedAt { get; set; } = DateTime.Now;
    public string Status { get; set; } = "Open";
    public string Priority { get; set; } = "Normal";

    public string? CreatedBy { get; set; }
    public IdentityUser Creator { get; set; } = null!;
    public string? AssignedTo { get; set; }
    public IdentityUser? Assignee { get; set; }

    public ICollection<TicketComment> Comments { get; set; } = null!;
    public ICollection<TicketHistory> Histories { get; set; } = null!;
    public TicketReview Review { get; set; } = null!;

    public string? ImageUrl { get; set; } 
}
