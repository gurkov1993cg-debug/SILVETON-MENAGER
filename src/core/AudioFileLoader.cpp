#include "silveton/manager/AudioFileLoader.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

namespace silveton::manager {
namespace {

std::uint16_t le16(const std::uint8_t* p) noexcept { return static_cast<std::uint16_t>(p[0]) | static_cast<std::uint16_t>(static_cast<std::uint16_t>(p[1]) << 8U); }
std::uint32_t le32(const std::uint8_t* p) noexcept { return static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8U) | (static_cast<std::uint32_t>(p[2]) << 16U) | (static_cast<std::uint32_t>(p[3]) << 24U); }
std::uint16_t be16(const std::uint8_t* p) noexcept { return static_cast<std::uint16_t>(static_cast<std::uint16_t>(p[0]) << 8U) | static_cast<std::uint16_t>(p[1]); }
std::uint32_t be32(const std::uint8_t* p) noexcept { return (static_cast<std::uint32_t>(p[0]) << 24U) | (static_cast<std::uint32_t>(p[1]) << 16U) | (static_cast<std::uint32_t>(p[2]) << 8U) | static_cast<std::uint32_t>(p[3]); }

bool readAll(const std::string& path, std::vector<std::uint8_t>& bytes, std::string& error) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) { error = "Cannot open audio file: " + path; return false; }
    const auto size = in.tellg();
    if (size <= 0) { error = "Audio file is empty: " + path; return false; }
    in.seekg(0, std::ios::beg);
    bytes.resize(static_cast<std::size_t>(size));
    if (!in.read(reinterpret_cast<char*>(bytes.data()), size)) { error = "Failed to read audio file: " + path; return false; }
    return true;
}

std::string identity(const std::filesystem::path& path) {
    std::error_code ec;
    const auto canonical = std::filesystem::weakly_canonical(path, ec);
    return (ec ? path.lexically_normal() : canonical).generic_string();
}

std::string extensionLower(std::filesystem::path path) {
    std::string ext = path.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c){ return static_cast<char>(std::tolower(c)); });
    return ext;
}

double extended80(const std::uint8_t* p) noexcept {
    const bool negative = (p[0] & 0x80U) != 0U;
    const std::uint16_t exponent = static_cast<std::uint16_t>((static_cast<std::uint16_t>(p[0] & 0x7FU) << 8U) | p[1]);
    std::uint64_t mantissa = 0U;
    for (unsigned i = 0; i < 8U; ++i) mantissa = (mantissa << 8U) | p[2U + i];
    if (exponent == 0U && mantissa == 0U) return 0.0;
    if (exponent == 0x7FFFU) return std::numeric_limits<double>::infinity();
    const double fraction = static_cast<double>(mantissa) / 9223372036854775808.0;
    const double value = std::ldexp(fraction, static_cast<int>(exponent) - 16383);
    return negative ? -value : value;
}

} // namespace

AudioLoadResult AudioFileLoader::load(const std::string& path) {
    const auto ext = extensionLower(path);
    if (ext == ".wav" || ext == ".wave") return loadWav(path);
    if (ext == ".aif" || ext == ".aiff" || ext == ".aifc") return loadAiff(path);
    return {{}, "Unsupported audio extension: " + ext};
}

AudioLoadResult AudioFileLoader::loadWav(const std::string& path) {
    std::vector<std::uint8_t> bytes;
    std::string error;
    if (!readAll(path, bytes, error)) return {{}, error};
    if (bytes.size() < 12U || std::memcmp(bytes.data(), "RIFF", 4U) != 0 || std::memcmp(bytes.data()+8U, "WAVE", 4U) != 0) return {{}, "Invalid RIFF/WAVE header"};

    const std::uint8_t* fmt = nullptr; std::size_t fmtSize = 0U;
    const std::uint8_t* data = nullptr; std::size_t dataSize = 0U;
    const std::uint8_t* smpl = nullptr; std::size_t smplSize = 0U;
    std::size_t pos = 12U;
    while (pos + 8U <= bytes.size()) {
        const std::uint32_t size = le32(bytes.data()+pos+4U);
        const std::size_t payload = pos + 8U;
        if (payload > bytes.size() || size > bytes.size() - payload) return {{}, "Corrupt WAV chunk size"};
        if (std::memcmp(bytes.data()+pos, "fmt ", 4U) == 0) { fmt = bytes.data()+payload; fmtSize=size; }
        else if (std::memcmp(bytes.data()+pos, "data", 4U) == 0) { data=bytes.data()+payload; dataSize=size; }
        else if (std::memcmp(bytes.data()+pos, "smpl", 4U) == 0) { smpl=bytes.data()+payload; smplSize=size; }
        pos = payload + size + (size & 1U);
    }
    if (fmt == nullptr || fmtSize < 16U || data == nullptr) return {{}, "WAV requires fmt and data chunks"};
    const std::uint16_t format = le16(fmt);
    const std::uint16_t channels = le16(fmt+2U);
    const std::uint32_t sampleRate = le32(fmt+4U);
    const std::uint16_t blockAlign = le16(fmt+12U);
    const std::uint16_t bits = le16(fmt+14U);
    if (channels == 0U || channels > 2U || sampleRate == 0U) return {{}, "Unsupported WAV channel/rate configuration"};

    AudioEncoding encoding{};
    if (format == 1U && bits == 16U) encoding=AudioEncoding::Pcm16LE;
    else if (format == 1U && bits == 24U) encoding=AudioEncoding::Pcm24LE;
    else if (format == 3U && bits == 32U) encoding=AudioEncoding::Float32LE;
    else return {{}, "WAV supports PCM16, PCM24 or IEEE float32 only"};
    const std::uint32_t expectedAlign = static_cast<std::uint32_t>(channels) * (bits/8U);
    if (blockAlign != expectedAlign || blockAlign == 0U || dataSize % blockAlign != 0U) return {{}, "Invalid WAV block alignment/data size"};

    ImportedSample out{};
    out.name=std::filesystem::path(path).stem().string(); out.sourcePath=path; out.sourceIdentity=identity(path);
    out.sampleRate=sampleRate; out.channels=channels; out.encoding=encoding; out.bitsPerSample=static_cast<std::uint8_t>(bits);
    out.totalFrames=static_cast<std::uint64_t>(dataSize/blockAlign); out.audioData.assign(data,data+dataSize);
    if (smpl != nullptr && smplSize >= 36U) {
        const std::uint32_t unity = le32(smpl+12U); if (unity <= 127U) out.rootKey=static_cast<std::uint8_t>(unity);
        const std::uint32_t loopCount=le32(smpl+28U);
        if (loopCount>0U && smplSize>=60U) {
            const std::uint32_t type=le32(smpl+40U), start=le32(smpl+44U), endInclusive=le32(smpl+48U);
            if (type==0U && endInclusive>=start && static_cast<std::uint64_t>(endInclusive)<out.totalFrames) {
                out.loop.enabled=true; out.loop.startFrame=start; out.loop.endFrame=static_cast<std::uint64_t>(endInclusive)+1U;
            }
        }
    }
    if (!out.valid()) return {{}, "Decoded WAV failed validation"};
    return {std::move(out), {}};
}

AudioLoadResult AudioFileLoader::loadAiff(const std::string& path) {
    std::vector<std::uint8_t> bytes;
    std::string error;
    if (!readAll(path, bytes, error)) return {{}, error};
    if (bytes.size()<12U || std::memcmp(bytes.data(),"FORM",4U)!=0) return {{}, "Invalid AIFF FORM header"};
    const bool aifc=std::memcmp(bytes.data()+8U,"AIFC",4U)==0;
    if (!aifc && std::memcmp(bytes.data()+8U,"AIFF",4U)!=0) return {{}, "Unsupported AIFF FORM type"};

    const std::uint8_t* comm=nullptr; std::size_t commSize=0U;
    const std::uint8_t* ssnd=nullptr; std::size_t ssndSize=0U;
    const std::uint8_t* inst=nullptr; std::size_t instSize=0U;
    const std::uint8_t* mark=nullptr; std::size_t markSize=0U;
    std::size_t pos=12U;
    while(pos+8U<=bytes.size()){
        const std::uint32_t size=be32(bytes.data()+pos+4U); const std::size_t payload=pos+8U;
        if(payload>bytes.size()||size>bytes.size()-payload)return {{} ,"Corrupt AIFF chunk size"};
        if(std::memcmp(bytes.data()+pos,"COMM",4U)==0){comm=bytes.data()+payload;commSize=size;}
        else if(std::memcmp(bytes.data()+pos,"SSND",4U)==0){ssnd=bytes.data()+payload;ssndSize=size;}
        else if(std::memcmp(bytes.data()+pos,"INST",4U)==0){inst=bytes.data()+payload;instSize=size;}
        else if(std::memcmp(bytes.data()+pos,"MARK",4U)==0){mark=bytes.data()+payload;markSize=size;}
        pos=payload+size+(size&1U);
    }
    if(comm==nullptr||commSize<18U||ssnd==nullptr||ssndSize<8U)return {{} ,"AIFF requires COMM and SSND chunks"};
    const std::uint16_t channels=be16(comm); const std::uint32_t frames=be32(comm+2U); const std::uint16_t bits=be16(comm+6U);
    const double srDouble=extended80(comm+8U); if(!(srDouble>=1.0&&srDouble<=768000.0))return {{} ,"Invalid AIFF sample rate"};
    const std::uint32_t sampleRate=static_cast<std::uint32_t>(std::llround(srDouble));
    if(channels==0U||channels>2U||(bits!=16U&&bits!=24U))return {{} ,"AIFF supports PCM16/PCM24 mono/stereo only"};
    bool sourceLittleEndian=false;
    if(aifc){
        if(commSize<22U)return {{} ,"AIFC COMM chunk is too short"};
        if(std::memcmp(comm+18U,"NONE",4U)==0)sourceLittleEndian=false;
        else if(std::memcmp(comm+18U,"sowt",4U)==0)sourceLittleEndian=true;
        else return {{} ,"Unsupported AIFC compression"};
    }
    const std::uint32_t offset=be32(ssnd); const std::size_t pcmStart=8U+offset;
    if(pcmStart>ssndSize)return {{} ,"Invalid AIFF SSND offset"};
    const std::uint32_t bps=bits/8U; const std::uint64_t expected=static_cast<std::uint64_t>(frames)*channels*bps;
    if(expected>ssndSize-pcmStart)return {{} ,"AIFF SSND payload is truncated"};
    ImportedSample out{}; out.name=std::filesystem::path(path).stem().string(); out.sourcePath=path; out.sourceIdentity=identity(path);
    out.sampleRate=sampleRate; out.channels=channels; out.bitsPerSample=static_cast<std::uint8_t>(bits); out.encoding=bits==16U?AudioEncoding::Pcm16LE:AudioEncoding::Pcm24LE; out.totalFrames=frames;
    const std::uint8_t* source=ssnd+pcmStart; out.audioData.resize(static_cast<std::size_t>(expected));
    if(sourceLittleEndian)std::copy(source,source+expected,out.audioData.begin());
    else for(std::size_t i=0;i<expected;i+=bps)for(std::uint32_t b=0;b<bps;++b)out.audioData[i+b]=source[i+(bps-1U-b)];

    if(inst!=nullptr&&instSize>=20U){
        out.rootKey=inst[0U];
        if(mark!=nullptr&&markSize>=2U){
            std::unordered_map<std::uint16_t,std::uint32_t> markers; std::size_t mp=2U; const std::uint16_t count=be16(mark);
            for(std::uint16_t i=0;i<count&&mp+7U<=markSize;++i){
                const std::uint16_t id=be16(mark+mp); const std::uint32_t position=be32(mark+mp+2U); const std::uint8_t len=mark[mp+6U];
                const std::size_t record=7U+len+((len&1U)==0U?1U:0U); if(mp+record>markSize)break; markers[id]=position; mp+=record;
            }
            const std::uint16_t playMode=be16(inst+8U), beginId=be16(inst+10U), endId=be16(inst+12U);
            const auto begin=markers.find(beginId), end=markers.find(endId);
            if(playMode==1U&&begin!=markers.end()&&end!=markers.end()&&end->second>begin->second&&end->second<=out.totalFrames){
                out.loop.enabled=true; out.loop.startFrame=begin->second; out.loop.endFrame=end->second;
            }
        }
    }
    if(!out.valid())return {{} ,"Decoded AIFF failed validation"};
    return {std::move(out),{}};
}

} // namespace silveton::manager
