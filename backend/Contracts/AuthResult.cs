namespace Tickify.Contracts
{
    public record AuthResult(
    bool Success,
    string Email,
    string Username,
    string Token
)
    {
        public Dictionary<string, string> ErrorMessages { get; init; } = new();
    }
}
