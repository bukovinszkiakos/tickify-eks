using Tickify.Context;
using Tickify.Models;
using Microsoft.EntityFrameworkCore;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Tickify.Repositories
{
    public class TicketCommentRepository : ITicketCommentRepository
    {
        private readonly ApplicationDbContext _context;

        public TicketCommentRepository(ApplicationDbContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<TicketComment>> GetCommentsByTicketIdAsync(int ticketId)
        {
            return await _context.TicketComments
                .Where(c => c.TicketId == ticketId)
                .OrderBy(c => c.CreatedAt)
                .ToListAsync();
        }

        public async Task AddCommentAsync(TicketComment comment)
        {
            await _context.TicketComments.AddAsync(comment);
        }

        public async Task SaveChangesAsync()
        {
            await _context.SaveChangesAsync();
        }
    }
}
