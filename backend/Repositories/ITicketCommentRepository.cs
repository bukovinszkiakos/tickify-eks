using Tickify.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Tickify.Repositories
{
    public interface ITicketCommentRepository
    {
        Task<IEnumerable<TicketComment>> GetCommentsByTicketIdAsync(int ticketId);
        Task AddCommentAsync(TicketComment comment);
        Task SaveChangesAsync();
    }
}
