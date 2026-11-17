import CoreGraphics
import Foundation
import WebP

/// libwebp encoder with the settings upstream passed to `cwebp`: `-q` quality, `-mt` (thread_level 1) and
/// `-metadata icc` (the source colour profile is embedded as an ICCP chunk).
enum WebPEncoder {
    static func encode(_ image: CGImage, quality: Float, multithreaded: Bool, keepICC: Bool) throws -> Data {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= 16383, h <= 16383 else { throw FWError(L("图片太大，WebP 最大 16383×16383")) }
        let space = ImageOps.space(for: image)
        // Premultiplied RGBA → straight RGBA (libwebp expects non-premultiplied samples).
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let base = ctx.data else {
            throw FWError(L("WebP 编码失败"))
        }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = base.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var opaque = true
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let a = px[i + 3]
            if a == 255 { continue }
            opaque = false
            if a == 0 { continue }
            for c in 0..<3 { px[i + c] = UInt8(min(255, (Int(px[i + c]) * 255 + Int(a) / 2) / Int(a))) }
        }

        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw FWError(L("WebP 编码失败")) }
        config.quality = quality
        config.thread_level = multithreaded ? 1 : 0
        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw FWError(L("WebP 编码失败")) }
        picture.use_argb = 1
        picture.width = Int32(w)
        picture.height = Int32(h)
        defer { WebPPictureFree(&picture) }
        let imported = opaque ? WebPPictureImportRGBX(&picture, px, Int32(w * 4)) : WebPPictureImportRGBA(&picture, px, Int32(w * 4))
        guard imported != 0 else { throw FWError(L("WebP 编码失败")) }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        withUnsafeMutablePointer(to: &writer) { picture.custom_ptr = UnsafeMutableRawPointer($0) }
        guard WebPEncode(&config, &picture) != 0, let mem = writer.mem else {
            throw FWError(L("WebP 编码失败（错误 %lld）", Int(picture.error_code.rawValue)))
        }
        let bitstream = Data(bytes: mem, count: writer.size)

        guard keepICC, let icc = space.copyICCData() as Data?, !isSRGB(space) else { return bitstream }
        return try addICC(icc, to: bitstream)
    }

    private static func isSRGB(_ space: CGColorSpace) -> Bool {
        (space.name as String?) == (CGColorSpace.sRGB as String)
    }

    /// Wraps the bitstream in a WebP container with an ICCP chunk (what `cwebp -metadata icc` produces).
    private static func addICC(_ icc: Data, to bitstream: Data) throws -> Data {
        guard let mux = WebPMuxNew() else { throw FWError(L("WebP 编码失败")) }
        defer { WebPMuxDelete(mux) }
        return try bitstream.withUnsafeBytes { (bs: UnsafeRawBufferPointer) -> Data in
            try icc.withUnsafeBytes { (ic: UnsafeRawBufferPointer) -> Data in
                var image = WebPData(bytes: bs.bindMemory(to: UInt8.self).baseAddress, size: bs.count)
                var profile = WebPData(bytes: ic.bindMemory(to: UInt8.self).baseAddress, size: ic.count)
                guard WebPMuxSetImage(mux, &image, 1) == WEBP_MUX_OK,
                      WebPMuxSetChunk(mux, "ICCP", &profile, 1) == WEBP_MUX_OK else { throw FWError(L("WebP 编码失败")) }
                var assembled = WebPData()
                guard WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK, let bytes = assembled.bytes else { throw FWError(L("WebP 编码失败")) }
                defer { WebPDataClear(&assembled) }
                return Data(bytes: bytes, count: assembled.size)
            }
        }
    }
}
