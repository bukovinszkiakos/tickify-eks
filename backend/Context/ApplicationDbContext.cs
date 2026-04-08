using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Tickify.Models;

namespace Tickify.Context
{
    public class ApplicationDbContext : IdentityDbContext<IdentityUser, IdentityRole, string>
    {
        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
            : base(options)
        {
        }

        public DbSet<Ticket> Tickets { get; set; }
        public DbSet<TicketComment> TicketComments { get; set; }
        public DbSet<TicketHistory> TicketHistories { get; set; }
        public DbSet<TicketReview> TicketReviews { get; set; }

        public DbSet<Notification> Notifications { get; set; }

        public DbSet<CommentReadStatus> CommentReadStatuses { get; set; }



        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<Ticket>()
                .HasOne(t => t.Assignee)
                .WithMany()
                .HasForeignKey(t => t.AssignedTo)
                .OnDelete(DeleteBehavior.SetNull);

            modelBuilder.Entity<Ticket>()
                .HasOne(t => t.Creator)
                .WithMany()
                .HasForeignKey(t => t.CreatedBy)
                .OnDelete(DeleteBehavior.NoAction);  
        }

    }
}
