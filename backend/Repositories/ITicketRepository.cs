using Tickify.Models;

namespace Tickify.Repositories
{
    public interface ITicketRepository
    {
        Task<IEnumerable<Ticket>> GetAllTicketsAsync();
        Task<Ticket> GetTicketByIdAsync(int id);
        Task AddTicketAsync(Ticket ticket);
        void UpdateTicket(Ticket ticket);
        void DeleteTicket(Ticket ticket);
        Task SaveChangesAsync();
        Task<IEnumerable<Ticket>> GetTicketsByUserAsync(string userId);
    }

}
