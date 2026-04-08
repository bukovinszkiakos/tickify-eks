using Microsoft.EntityFrameworkCore;
using Tickify.Context;
using Tickify.Models;

namespace Tickify.Repositories
{
    public class TicketRepository : ITicketRepository
    {
        private readonly ApplicationDbContext _context;

        public TicketRepository(ApplicationDbContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<Ticket>> GetAllTicketsAsync()
        {
            return await _context.Tickets.ToListAsync();
        }

        public async Task<Ticket> GetTicketByIdAsync(int id)
        {
            return await _context.Tickets.FindAsync(id);
        }

        public async Task AddTicketAsync(Ticket ticket)
        {
            await _context.Tickets.AddAsync(ticket);
        }

        public void UpdateTicket(Ticket ticket)
        {
            _context.Tickets.Update(ticket);
        }

        public void DeleteTicket(Ticket ticket)
        {
            _context.Tickets.Remove(ticket);
        }

        public async Task SaveChangesAsync()
        {
            await _context.SaveChangesAsync();
        }

        public async Task<IEnumerable<Ticket>> GetTicketsByUserAsync(string userId)
        {
            return await _context.Tickets
                .Where(t => t.CreatedBy == userId)
                .ToListAsync();
        }
    }

}
