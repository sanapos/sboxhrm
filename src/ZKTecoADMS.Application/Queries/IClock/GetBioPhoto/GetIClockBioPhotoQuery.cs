using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Queries.IClock.GetBioPhoto;

/// <summary>JPEG for VL device fetching DATA UPDATE BIOPHOTO Url=iclock/doc/biophoto/{id}.jpg</summary>
public record GetIClockBioPhotoQuery(Guid FaceTemplateId) : IQuery<byte[]>;

public class GetIClockBioPhotoHandler(
    IRepository<FaceTemplate> faceRepository
) : IQueryHandler<GetIClockBioPhotoQuery, byte[]>
{
    public async Task<byte[]> Handle(GetIClockBioPhotoQuery request, CancellationToken cancellationToken)
    {
        var face = await faceRepository.GetByIdAsync(request.FaceTemplateId);
        if (face == null)
            return [];

        return BioPhotoCodec.TryGetJpeg(face.Template, face.PhotoData) ?? [];
    }
}
