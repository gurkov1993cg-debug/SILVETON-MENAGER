#include "silveton/manager/SvBankFormat.h"

#include <algorithm>
#include <array>
#include <cstring>

namespace silveton::manager {
namespace {

void appendU8(std::vector<std::uint8_t>& out, std::uint8_t value) { out.push_back(value); }
void appendI8(std::vector<std::uint8_t>& out, std::int8_t value) { out.push_back(static_cast<std::uint8_t>(value)); }
void appendU16(std::vector<std::uint8_t>& out, std::uint16_t value) {
    out.push_back(static_cast<std::uint8_t>(value & 0xFFU));
    out.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
}
void appendU32(std::vector<std::uint8_t>& out, std::uint32_t value) {
    for (unsigned i = 0; i < 4U; ++i) out.push_back(static_cast<std::uint8_t>((value >> (i * 8U)) & 0xFFU));
}
void appendU64(std::vector<std::uint8_t>& out, std::uint64_t value) {
    for (unsigned i = 0; i < 8U; ++i) out.push_back(static_cast<std::uint8_t>((value >> (i * 8U)) & 0xFFU));
}
void appendF32(std::vector<std::uint8_t>& out, float value) {
    std::uint32_t bits = 0U;
    static_assert(sizeof(bits) == sizeof(value), "float must be 32-bit");
    std::memcpy(&bits, &value, sizeof(bits));
    appendU32(out, bits);
}

bool readU8(const std::uint8_t*& p, const std::uint8_t* end, std::uint8_t& value) noexcept {
    if (p >= end) return false;
    value = *p++;
    return true;
}
bool readI8(const std::uint8_t*& p, const std::uint8_t* end, std::int8_t& value) noexcept {
    std::uint8_t raw = 0U;
    if (!readU8(p, end, raw)) return false;
    value = static_cast<std::int8_t>(raw);
    return true;
}
bool readU16(const std::uint8_t*& p, const std::uint8_t* end, std::uint16_t& value) noexcept {
    if (static_cast<std::size_t>(end - p) < 2U) return false;
    value = static_cast<std::uint16_t>(p[0]) |
            static_cast<std::uint16_t>(static_cast<std::uint16_t>(p[1]) << 8U);
    p += 2;
    return true;
}
bool readU32(const std::uint8_t*& p, const std::uint8_t* end, std::uint32_t& value) noexcept {
    if (static_cast<std::size_t>(end - p) < 4U) return false;
    value = static_cast<std::uint32_t>(p[0]) |
            (static_cast<std::uint32_t>(p[1]) << 8U) |
            (static_cast<std::uint32_t>(p[2]) << 16U) |
            (static_cast<std::uint32_t>(p[3]) << 24U);
    p += 4;
    return true;
}
bool readU64(const std::uint8_t*& p, const std::uint8_t* end, std::uint64_t& value) noexcept {
    if (static_cast<std::size_t>(end - p) < 8U) return false;
    value = 0U;
    for (unsigned i = 0; i < 8U; ++i) value |= static_cast<std::uint64_t>(p[i]) << (i * 8U);
    p += 8;
    return true;
}
bool readF32(const std::uint8_t*& p, const std::uint8_t* end, float& value) noexcept {
    std::uint32_t bits = 0U;
    if (!readU32(p, end, bits)) return false;
    std::memcpy(&value, &bits, sizeof(value));
    return true;
}

void padTo(std::vector<std::uint8_t>& out, std::size_t size) {
    if (out.size() < size) out.resize(size, 0U);
}

std::uint32_t rotr(std::uint32_t x, std::uint32_t n) noexcept { return (x >> n) | (x << (32U - n)); }

} // namespace

std::vector<std::uint8_t> serializeHeader(const SvBankHeader& header) {
    std::vector<std::uint8_t> out;
    out.reserve(kSvBankHeaderSize);
    out.insert(out.end(), kSvBankMagic.begin(), kSvBankMagic.end());
    appendU16(out, header.versionMajor);
    appendU16(out, header.versionMinor);
    appendU32(out, kSvBankHeaderSize);
    appendU32(out, header.flags);
    appendU64(out, header.fileSize);
    appendU32(out, header.bankNameOffset);
    appendU32(out, header.soundCount);
    appendU32(out, header.soundLayerCount);
    appendU32(out, header.multisampleCount);
    appendU32(out, header.sampleCount);
    appendU32(out, header.zoneCount);
    for (const auto& section : header.sections) {
        appendU64(out, section.offset);
        appendU64(out, section.size);
    }
    out.insert(out.end(), header.payloadSha256.begin(), header.payloadSha256.end());
    padTo(out, kSvBankHeaderSize);
    return out;
}

bool deserializeHeader(const std::uint8_t* data, std::size_t size, SvBankHeader& header, std::string& error) {
    if (data == nullptr || size < kSvBankHeaderSize) { error = "SV bank header is truncated"; return false; }
    if (!std::equal(kSvBankMagic.begin(), kSvBankMagic.end(), data)) { error = "SV bank magic mismatch"; return false; }
    const std::uint8_t* p = data + kSvBankMagic.size();
    const std::uint8_t* end = data + kSvBankHeaderSize;
    std::uint32_t headerSize = 0U;
    if (!readU16(p, end, header.versionMajor) || !readU16(p, end, header.versionMinor) ||
        !readU32(p, end, headerSize) || !readU32(p, end, header.flags) || !readU64(p, end, header.fileSize) ||
        !readU32(p, end, header.bankNameOffset) || !readU32(p, end, header.soundCount) ||
        !readU32(p, end, header.soundLayerCount) || !readU32(p, end, header.multisampleCount) ||
        !readU32(p, end, header.sampleCount) || !readU32(p, end, header.zoneCount)) {
        error = "SV bank header fields are truncated";
        return false;
    }
    if (headerSize != kSvBankHeaderSize) { error = "Unsupported SV bank header size"; return false; }
    if (header.versionMajor != kSvBankVersionMajor) { error = "Unsupported SV bank major version"; return false; }
    for (auto& section : header.sections) {
        if (!readU64(p, end, section.offset) || !readU64(p, end, section.size)) {
            error = "SV bank section table is truncated";
            return false;
        }
    }
    if (static_cast<std::size_t>(end - p) < header.payloadSha256.size()) {
        error = "SV bank integrity field is truncated";
        return false;
    }
    std::copy_n(p, header.payloadSha256.size(), header.payloadSha256.begin());
    error.clear();
    return true;
}

void appendSoundRecord(std::vector<std::uint8_t>& out, const SvSoundRecord& r) {
    const std::size_t start = out.size();
    appendU32(out, r.nameOffset); appendU32(out, r.firstLayer); appendU32(out, r.layerCount);
    appendU16(out, r.bank); appendU16(out, r.page); appendU16(out, r.slot); appendU16(out, r.category);
    padTo(out, start + kSvSoundRecordSize);
}

void appendSoundLayerRecord(std::vector<std::uint8_t>& out, const SvSoundLayerRecord& r) {
    const std::size_t start = out.size();
    appendU32(out, r.multisampleIndex); appendU8(out, r.enabled); appendU8(out, r.keyLow); appendU8(out, r.keyHigh);
    appendU8(out, r.velocityLow); appendU8(out, r.velocityHigh); appendI8(out, r.transposeSemitones);
    appendF32(out, r.tuneCents); appendF32(out, r.levelDb); appendF32(out, r.pan);
    padTo(out, start + kSvSoundLayerRecordSize);
}

void appendMultisampleRecord(std::vector<std::uint8_t>& out, const SvMultisampleRecord& r) {
    const std::size_t start = out.size();
    appendU32(out, r.nameOffset); appendU32(out, r.sourceIdentityOffset); appendU32(out, r.firstZone); appendU32(out, r.zoneCount);
    padTo(out, start + kSvMultisampleRecordSize);
}

void appendSampleRecord(std::vector<std::uint8_t>& out, const SvSampleRecord& r) {
    const std::size_t start = out.size();
    appendU32(out, r.nameOffset); appendU32(out, r.sourceIdentityOffset); appendU32(out, r.sampleRate); appendU16(out, r.channels);
    appendU8(out, r.encoding); appendU8(out, r.bitsPerSample); appendU8(out, r.rootKey); appendU8(out, r.loopEnabled);
    appendF32(out, r.fineTuneCents); appendU64(out, r.totalFrames); appendU64(out, r.loopStart); appendU64(out, r.loopEnd);
    appendU32(out, r.loopCrossfadeFrames); appendU64(out, r.audioOffset); appendU64(out, r.audioSize); appendU64(out, r.audioHash);
    padTo(out, start + kSvSampleRecordSize);
}

void appendZoneRecord(std::vector<std::uint8_t>& out, const SvZoneRecord& r) {
    const std::size_t start = out.size();
    appendU32(out, r.sampleIndex); appendU8(out, r.keyLow); appendU8(out, r.keyHigh); appendU8(out, r.velocityLow); appendU8(out, r.velocityHigh);
    appendU8(out, r.rootKey); appendI8(out, r.transposeSemitones); appendU8(out, r.flags); appendU8(out, r.sourcePanRaw);
    appendI8(out, r.sourceLevelRaw); appendI8(out, r.sourceFilterRaw); appendF32(out, r.tuneCents); appendF32(out, r.gainDb); appendF32(out, r.pan);
    padTo(out, start + kSvZoneRecordSize);
}

bool readSoundRecord(const std::uint8_t* data, std::size_t size, SvSoundRecord& r) {
    if (data == nullptr || size < kSvSoundRecordSize) return false;
    const std::uint8_t* p = data; const std::uint8_t* end = data + kSvSoundRecordSize;
    return readU32(p,end,r.nameOffset) && readU32(p,end,r.firstLayer) && readU32(p,end,r.layerCount) &&
           readU16(p,end,r.bank) && readU16(p,end,r.page) && readU16(p,end,r.slot) && readU16(p,end,r.category);
}

bool readSoundLayerRecord(const std::uint8_t* data, std::size_t size, SvSoundLayerRecord& r) {
    if (data == nullptr || size < kSvSoundLayerRecordSize) return false;
    const std::uint8_t* p=data; const std::uint8_t* end=data+kSvSoundLayerRecordSize;
    return readU32(p,end,r.multisampleIndex) && readU8(p,end,r.enabled) && readU8(p,end,r.keyLow) && readU8(p,end,r.keyHigh) &&
           readU8(p,end,r.velocityLow) && readU8(p,end,r.velocityHigh) && readI8(p,end,r.transposeSemitones) &&
           readF32(p,end,r.tuneCents) && readF32(p,end,r.levelDb) && readF32(p,end,r.pan);
}

bool readMultisampleRecord(const std::uint8_t* data, std::size_t size, SvMultisampleRecord& r) {
    if (data == nullptr || size < kSvMultisampleRecordSize) return false;
    const std::uint8_t* p=data; const std::uint8_t* end=data+kSvMultisampleRecordSize;
    return readU32(p,end,r.nameOffset) && readU32(p,end,r.sourceIdentityOffset) && readU32(p,end,r.firstZone) && readU32(p,end,r.zoneCount);
}

bool readSampleRecord(const std::uint8_t* data, std::size_t size, SvSampleRecord& r) {
    if (data == nullptr || size < kSvSampleRecordSize) return false;
    const std::uint8_t* p=data; const std::uint8_t* end=data+kSvSampleRecordSize;
    return readU32(p,end,r.nameOffset) && readU32(p,end,r.sourceIdentityOffset) && readU32(p,end,r.sampleRate) && readU16(p,end,r.channels) &&
           readU8(p,end,r.encoding) && readU8(p,end,r.bitsPerSample) && readU8(p,end,r.rootKey) && readU8(p,end,r.loopEnabled) &&
           readF32(p,end,r.fineTuneCents) && readU64(p,end,r.totalFrames) && readU64(p,end,r.loopStart) && readU64(p,end,r.loopEnd) &&
           readU32(p,end,r.loopCrossfadeFrames) && readU64(p,end,r.audioOffset) && readU64(p,end,r.audioSize) && readU64(p,end,r.audioHash);
}

bool readZoneRecord(const std::uint8_t* data, std::size_t size, SvZoneRecord& r) {
    if (data == nullptr || size < kSvZoneRecordSize) return false;
    const std::uint8_t* p=data; const std::uint8_t* end=data+kSvZoneRecordSize;
    return readU32(p,end,r.sampleIndex) && readU8(p,end,r.keyLow) && readU8(p,end,r.keyHigh) && readU8(p,end,r.velocityLow) && readU8(p,end,r.velocityHigh) &&
           readU8(p,end,r.rootKey) && readI8(p,end,r.transposeSemitones) && readU8(p,end,r.flags) && readU8(p,end,r.sourcePanRaw) &&
           readI8(p,end,r.sourceLevelRaw) && readI8(p,end,r.sourceFilterRaw) && readF32(p,end,r.tuneCents) && readF32(p,end,r.gainDb) && readF32(p,end,r.pan);
}

std::array<std::uint8_t, 32> sha256(const std::uint8_t* data, std::size_t size) noexcept {
    constexpr std::array<std::uint32_t, 64> k{{
        0x428a2f98U,0x71374491U,0xb5c0fbcfU,0xe9b5dba5U,0x3956c25bU,0x59f111f1U,0x923f82a4U,0xab1c5ed5U,
        0xd807aa98U,0x12835b01U,0x243185beU,0x550c7dc3U,0x72be5d74U,0x80deb1feU,0x9bdc06a7U,0xc19bf174U,
        0xe49b69c1U,0xefbe4786U,0x0fc19dc6U,0x240ca1ccU,0x2de92c6fU,0x4a7484aaU,0x5cb0a9dcU,0x76f988daU,
        0x983e5152U,0xa831c66dU,0xb00327c8U,0xbf597fc7U,0xc6e00bf3U,0xd5a79147U,0x06ca6351U,0x14292967U,
        0x27b70a85U,0x2e1b2138U,0x4d2c6dfcU,0x53380d13U,0x650a7354U,0x766a0abbU,0x81c2c92eU,0x92722c85U,
        0xa2bfe8a1U,0xa81a664bU,0xc24b8b70U,0xc76c51a3U,0xd192e819U,0xd6990624U,0xf40e3585U,0x106aa070U,
        0x19a4c116U,0x1e376c08U,0x2748774cU,0x34b0bcb5U,0x391c0cb3U,0x4ed8aa4aU,0x5b9cca4fU,0x682e6ff3U,
        0x748f82eeU,0x78a5636fU,0x84c87814U,0x8cc70208U,0x90befffaU,0xa4506cebU,0xbef9a3f7U,0xc67178f2U
    }};
    std::array<std::uint32_t,8> h{{0x6a09e667U,0xbb67ae85U,0x3c6ef372U,0xa54ff53aU,0x510e527fU,0x9b05688cU,0x1f83d9abU,0x5be0cd19U}};
    const std::uint64_t bitLength = static_cast<std::uint64_t>(size) * 8U;
    const std::size_t paddedSize = ((size + 9U + 63U) / 64U) * 64U;
    std::array<std::uint8_t,64> block{};
    for (std::size_t blockStart=0; blockStart<paddedSize; blockStart+=64U) {
        block.fill(0U);
        for (std::size_t i=0;i<64U;++i) {
            const std::size_t index=blockStart+i;
            if (index<size) block[i]=data[index];
            else if (index==size) block[i]=0x80U;
        }
        if (blockStart + 64U == paddedSize) {
            for (unsigned i=0;i<8U;++i) block[63U-i]=static_cast<std::uint8_t>((bitLength>>(i*8U))&0xFFU);
        }
        std::array<std::uint32_t,64> w{};
        for (std::size_t i=0;i<16U;++i) {
            const std::size_t j=i*4U;
            w[i]=(static_cast<std::uint32_t>(block[j])<<24U)|(static_cast<std::uint32_t>(block[j+1U])<<16U)|
                 (static_cast<std::uint32_t>(block[j+2U])<<8U)|static_cast<std::uint32_t>(block[j+3U]);
        }
        for (std::size_t i=16U;i<64U;++i) {
            const std::uint32_t s0=rotr(w[i-15U],7U)^rotr(w[i-15U],18U)^(w[i-15U]>>3U);
            const std::uint32_t s1=rotr(w[i-2U],17U)^rotr(w[i-2U],19U)^(w[i-2U]>>10U);
            w[i]=w[i-16U]+s0+w[i-7U]+s1;
        }
        std::uint32_t a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
        for (std::size_t i=0;i<64U;++i) {
            const std::uint32_t s1=rotr(e,6U)^rotr(e,11U)^rotr(e,25U);
            const std::uint32_t ch=(e&f)^((~e)&g);
            const std::uint32_t temp1=hh+s1+ch+k[i]+w[i];
            const std::uint32_t s0=rotr(a,2U)^rotr(a,13U)^rotr(a,22U);
            const std::uint32_t maj=(a&b)^(a&c)^(b&c);
            const std::uint32_t temp2=s0+maj;
            hh=g; g=f; f=e; e=d+temp1; d=c; c=b; b=a; a=temp1+temp2;
        }
        h[0]+=a;h[1]+=b;h[2]+=c;h[3]+=d;h[4]+=e;h[5]+=f;h[6]+=g;h[7]+=hh;
    }
    std::array<std::uint8_t,32> out{};
    for (std::size_t i=0;i<h.size();++i) {
        out[i*4U]=static_cast<std::uint8_t>((h[i]>>24U)&0xFFU);
        out[i*4U+1U]=static_cast<std::uint8_t>((h[i]>>16U)&0xFFU);
        out[i*4U+2U]=static_cast<std::uint8_t>((h[i]>>8U)&0xFFU);
        out[i*4U+3U]=static_cast<std::uint8_t>(h[i]&0xFFU);
    }
    return out;
}

} // namespace silveton::manager
