using Amazon.S3;
using Amazon.S3.Model;

namespace Tickify.Services.FileStorage
{
    public class S3FileStorageService : IFileStorageService
    {
        private readonly IAmazonS3 _s3Client;
        private readonly string _bucketName;

        public S3FileStorageService(IAmazonS3 s3Client, IConfiguration config)
        {
            _s3Client = s3Client;
            _bucketName = config["AWS:BucketName"]
                ?? throw new InvalidOperationException(
                    "AWS:BucketName is not configured. Set the AWS__BucketName environment variable.");
        }

        public async Task<string> UploadFileAsync(Stream fileStream, string fileName, string contentType)
        {
            var key = $"{Guid.NewGuid()}_{fileName}";

            var request = new PutObjectRequest
            {
                BucketName = _bucketName,
                Key = key,
                InputStream = fileStream,
                ContentType = contentType
            };

            await _s3Client.PutObjectAsync(request);

            return key;
        }

        public Task<string?> GetFileUrlAsync(string key, int expiryMinutes = 60)
        {
            if (string.IsNullOrEmpty(key))
                return Task.FromResult<string?>(null);

            var request = new GetPreSignedUrlRequest
            {
                BucketName = _bucketName,
                Key = key,
                Expires = DateTime.UtcNow.AddMinutes(expiryMinutes),
                Verb = HttpVerb.GET
            };

            return Task.FromResult<string?>(_s3Client.GetPreSignedURL(request));
        }
    }
}