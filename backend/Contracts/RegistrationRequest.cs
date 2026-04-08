using System.ComponentModel.DataAnnotations;

namespace Tickify.Contracts
{
    public record RegistrationRequest(
     [Required] string Email,
     [Required] string Username,
     [Required] string Password
 );
}
