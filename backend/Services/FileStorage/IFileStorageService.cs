namespace Tickify.Services.FileStorage
{
    public interface IFileStorageService
    {
        Task<string> UploadFileAsync(Stream fileStream, string fileName, string contentType);
        Task<string?> GetFileUrlAsync(string key, int expiryMinutes = 60);
        Task DeleteFileAsync(string key);
    }
}