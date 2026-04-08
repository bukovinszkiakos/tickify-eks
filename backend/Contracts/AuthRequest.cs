using System.ComponentModel.DataAnnotations;

namespace Tickify.Contracts
{

    public record AuthRequest(
        [Required] string Email,
        [Required] string Password
    );

}
