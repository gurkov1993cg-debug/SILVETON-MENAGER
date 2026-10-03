#include "silveton/manager/AudioFileLoader.h"
#include "silveton/manager/KorgImporter.h"
#include "silveton/manager/SvBankBuilder.h"
#include "silveton/manager/SvBankFormat.h"
#include "silveton/manager/SvBankReader.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {

using Bytes = std::vector<std::uint8_t>;

void putBe16(Bytes& b, std::uint16_t v) { b.push_back(static_cast<std::uint8_t>((v>>8U)&0xFFU)); b.push_back(static_cast<std::uint8_t>(v&0xFFU)); }
void putBe32(Bytes& b, std::uint32_t v) { for(int s=24;s>=0;s-=8)b.push_back(static_cast<std::uint8_t>((v>>static_cast<unsigned>(s))&0xFFU)); }
void putLe16(Bytes& b, std::uint16_t v) { b.push_back(static_cast<std::uint8_t>(v&0xFFU)); b.push_back(static_cast<std::uint8_t>((v>>8U)&0xFFU)); }
void putLe32(Bytes& b, std::uint32_t v) { for(unsigned s=0;s<32U;s+=8U)b.push_back(static_cast<std::uint8_t>((v>>s)&0xFFU)); }

void setBe32(Bytes& b, std::size_t p, std::uint32_t v){b[p]=static_cast<std::uint8_t>((v>>24U)&0xFFU);b[p+1]=static_cast<std::uint8_t>((v>>16U)&0xFFU);b[p+2]=static_cast<std::uint8_t>((v>>8U)&0xFFU);b[p+3]=static_cast<std::uint8_t>(v&0xFFU);}
void setLe32(Bytes& b, std::size_t p, std::uint32_t v){b[p]=static_cast<std::uint8_t>(v&0xFFU);b[p+1]=static_cast<std::uint8_t>((v>>8U)&0xFFU);b[p+2]=static_cast<std::uint8_t>((v>>16U)&0xFFU);b[p+3]=static_cast<std::uint8_t>((v>>24U)&0xFFU);}

void chunkBe(Bytes& out, const char id[5], const Bytes& payload){out.insert(out.end(),id,id+4);putBe32(out,static_cast<std::uint32_t>(payload.size()));out.insert(out.end(),payload.begin(),payload.end());}
void chunkLe(Bytes& out, const char id[5], const Bytes& payload){out.insert(out.end(),id,id+4);putLe32(out,static_cast<std::uint32_t>(payload.size()));out.insert(out.end(),payload.begin(),payload.end());if(payload.size()&1U)out.push_back(0);}

[[noreturn]] void fail(const std::string& message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

void require(bool condition, const std::string& message) {
    if (!condition) fail(message);
}

std::string joinPath(const std::string& base, const std::string& leaf) {
    if (base.empty()) return leaf;
    if (base.back() == '/') return base + leaf;
    return base + "/" + leaf;
}

std::string testRoot() {
    const char* tmp = std::getenv("TMPDIR");
    const std::string base = (tmp != nullptr && tmp[0] != '\0') ? std::string(tmp) : std::string("/tmp");
    return joinPath(base, "silveton_manager_tests_" + std::to_string(static_cast<long long>(::getpid())));
}

void writeFile(const std::string& p,const Bytes& b){
    std::ofstream f(p,std::ios::binary);
    require(static_cast<bool>(f), "cannot create fixture file " + p);
    f.write(reinterpret_cast<const char*>(b.data()),static_cast<std::streamsize>(b.size()));
    require(f.good(), "cannot write fixture file " + p);
}

Bytes ksf(const std::string& name, const std::array<std::int16_t,4>& pcm){
    Bytes f,smp(32U,0U); for(std::size_t i=0;i<name.size()&&i<16U;++i)smp[i]=static_cast<std::uint8_t>(name[i]); setBe32(smp,24U,4U); setBe32(smp,28U,4U); chunkBe(f,"SMP1",smp);
    Bytes sno(4U,0U); chunkBe(f,"SNO1",sno);
    Bytes smd; putBe32(smd,48000U); smd.push_back(0xA0U); smd.push_back(0U); smd.push_back(1U); smd.push_back(16U); putBe32(smd,4U);
    for(auto s:pcm){const auto u=static_cast<std::uint16_t>(s);putBe16(smd,u);} chunkBe(f,"SMD1",smd); return f;
}

void fillName(Bytes& r,std::size_t off,const std::string& name,std::size_t n){for(std::size_t i=0;i<n;++i)r[off+i]=i<name.size()?static_cast<std::uint8_t>(name[i]):static_cast<std::uint8_t>(' ');}
Bytes kmp(){
    Bytes f,msp(18U,0U);fillName(msp,0,"FIXTURE",16U);msp[16]=3U;chunkBe(f,"MSP1",msp);Bytes mno(4U,0U);chunkBe(f,"MNO1",mno);
    Bytes rlp(54U,0U); rlp[0]=1U;rlp[1]=1U;fillName(rlp,6,"SKIPPEDSAMPL",12U);
    const std::size_t r1=18U;rlp[r1]=60U;rlp[r1+1]=63U;rlp[r1+4]=64U;fillName(rlp,r1+6,"A.KSF",12U);
    const std::size_t r2=36U;rlp[r2]=64U;rlp[r2+1]=127U;rlp[r2+4]=64U;fillName(rlp,r2+6,"B.KSF",12U);chunkBe(f,"RLP1",rlp);return f;
}

Bytes wav(){
    Bytes body; body.insert(body.end(),{'W','A','V','E'});
    Bytes fmt;putLe16(fmt,1U);putLe16(fmt,1U);putLe32(fmt,48000U);putLe32(fmt,96000U);putLe16(fmt,2U);putLe16(fmt,16U);chunkLe(body,"fmt ",fmt);
    Bytes smpl(60U,0U);setLe32(smpl,12U,64U);setLe32(smpl,28U,1U);setLe32(smpl,40U,0U);setLe32(smpl,44U,1U);setLe32(smpl,48U,2U);chunkLe(body,"smpl",smpl);
    Bytes data;const std::array<std::int16_t,4> samples{{std::numeric_limits<std::int16_t>::min(), static_cast<std::int16_t>(-1), 0, std::numeric_limits<std::int16_t>::max()}};for(const auto s:samples)putLe16(data,static_cast<std::uint16_t>(s));chunkLe(body,"data",data);
    Bytes out;out.insert(out.end(),{'R','I','F','F'});putLe32(out,static_cast<std::uint32_t>(body.size()));out.insert(out.end(),body.begin(),body.end());return out;
}

Bytes aiff(){
    Bytes body;body.insert(body.end(),{'A','I','F','F'});
    Bytes comm;putBe16(comm,1U);putBe32(comm,4U);putBe16(comm,16U);const std::array<std::uint8_t,10> rate{{0x40,0x0E,0xAC,0x44,0,0,0,0,0,0}};comm.insert(comm.end(),rate.begin(),rate.end());chunkBe(body,"COMM",comm);
    Bytes inst(20U,0U);inst[0]=65U;chunkBe(body,"INST",inst);
    Bytes ssnd;putBe32(ssnd,0U);putBe32(ssnd,0U);const std::array<std::int16_t,4> samples{{std::numeric_limits<std::int16_t>::min(), static_cast<std::int16_t>(-1), 0, std::numeric_limits<std::int16_t>::max()}};for(const auto s:samples)putBe16(ssnd,static_cast<std::uint16_t>(s));chunkBe(body,"SSND",ssnd);
    Bytes out;out.insert(out.end(),{'F','O','R','M'});putBe32(out,static_cast<std::uint32_t>(body.size()));out.insert(out.end(),body.begin(),body.end());return out;
}

std::string digestHex(const std::array<std::uint8_t,32>& d){std::ostringstream os;for(auto b:d)os<<std::hex<<std::setw(2)<<std::setfill('0')<<static_cast<unsigned>(b);return os.str();}

} // namespace

int main(){
    using namespace silveton::manager;
    const std::string root=testRoot();
    require(::mkdir(root.c_str(),0700)==0,"cannot create test directory " + root);

    const std::string ksfA=joinPath(root,"A.KSF");
    const std::string ksfB=joinPath(root,"B.KSF");
    const std::string kmpPath=joinPath(root,"FIXTURE.KMP");
    const std::string wavPath=joinPath(root,"fixture.wav");
    const std::string aiffPath=joinPath(root,"fixture.aiff");
    const std::string bank=joinPath(root,"SILVETON_BANK.sv");

    require(std::fabs(KorgImporter::normalizedPan(0U)+1.0F)<1e-6F, "pan raw 0 must map left");
    require(std::fabs(KorgImporter::normalizedPan(64U))<1e-6F, "pan raw 64 must map centre");
    require(std::fabs(KorgImporter::normalizedPan(127U)-1.0F)<1e-6F, "pan raw 127 must map right");

    writeFile(ksfA,ksf("C4",{{-32768,-100,100,32767}}));
    writeFile(ksfB,ksf("E4",{{-20000,-10,10,20000}}));
    writeFile(kmpPath,kmp());
    auto kr=KorgImporter::loadKmp(kmpPath);
    require(kr.ok(), "synthetic KMP import");
    require(kr.samples.size()==2U, "KMP sample count");
    require(kr.multisample.zones.size()==2U, "KMP zone count");
    require(kr.multisample.zones[0].keyLow==2U&&kr.multisample.zones[0].keyHigh==63U&&kr.multisample.zones[0].rootKey==60U, "first KMP zone/root");
    require(kr.multisample.zones[1].keyLow==64U&&kr.multisample.zones[1].keyHigh==127U, "second KMP zone");
    require(kr.multisample.zones[0].sourcePanRaw==64U&&std::fabs(kr.multisample.zones[0].pan)<1e-6F, "KMP raw pan preservation");
    require(kr.samples[0].sampleRate==48000U&&kr.samples[0].channels==1U&&!kr.samples[0].loop.enabled, "KSF format/no fake loop");

    writeFile(wavPath,wav());
    auto wr=AudioFileLoader::load(wavPath);
    require(wr.ok(), "WAV import");
    require(wr.sample.rootKey==64U&&wr.sample.loop.enabled&&wr.sample.loop.startFrame==1U&&wr.sample.loop.endFrame==3U&&wr.sample.totalFrames==4U, "WAV smpl root/loop");

    writeFile(aiffPath,aiff());
    auto ar=AudioFileLoader::load(aiffPath);
    require(ar.ok(), "AIFF import");
    require(ar.sample.sampleRate==44100U&&ar.sample.rootKey==65U&&ar.sample.totalFrames==4U, "AIFF rate/root/frame count");
    require(ar.sample.audioData[0]==0x00U&&ar.sample.audioData[1]==0x80U, "AIFF big-endian to canonical little-endian");

    const char* abc="abc";
    require(digestHex(sha256(reinterpret_cast<const std::uint8_t*>(abc),3U))=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 standard vector");

    BankProject project;project.name="TEST BANK";project.samples=kr.samples;project.multisamples.push_back(kr.multisample);
    SoundDefinition sound;sound.name="Fixture Sound";sound.bank=1U;sound.page=2U;sound.slot=3U;SoundLayer layer;layer.multisampleIndex=0U;sound.layers.push_back(layer);project.sounds.push_back(sound);
    auto duplicate=project.samples.front();duplicate.name="Duplicate Audio";project.samples.push_back(duplicate);

    auto built=SvBankBuilder::build(project);
    require(built.ok(), "SV bank build");
    require(built.stats.sampleCount==3U&&built.stats.uniqueAudioPayloadCount==2U&&built.stats.audioBytesAfterDedup<built.stats.audioBytesBeforeDedup, "SV audio dedup");

    auto round=SvBankReader::read(built.bytes,true);
    require(round.ok(), "SV bank read/verify");
    require(round.project.name==project.name&&round.project.samples.size()==3U&&round.project.multisamples.size()==1U&&round.project.sounds.size()==1U, "SV round-trip object counts");
    require(round.project.samples[0].audioData==project.samples[0].audioData, "SV exact audio round-trip");
    require(round.project.multisamples[0].zones[0].sourcePanRaw==64U, "SV raw Korg metadata round-trip");
    require(round.project.sounds[0].bank==1U&&round.project.sounds[0].page==2U&&round.project.sounds[0].slot==3U, "SV SOUND address round-trip");

    auto corrupt=built.bytes;corrupt.back()^=1U;
    require(!SvBankReader::read(corrupt,true).ok(), "SV corrupted payload rejection");

    BankProject invalid=project;invalid.multisamples[0].zones[0].sampleIndex=999U;
    require(!SvBankBuilder::build(invalid).ok(), "SV invalid reference rejection");

    SvBuildStats stats{};std::string error;
    require(SvBankBuilder::writeAtomic(bank,project,stats,error), "SV atomic write");
    require(error.empty(), "SV atomic write error state");
    require(stats.uniqueAudioPayloadCount==2U, "SV atomic write stats");
    require(SvBankReader::readFile(bank,true).ok(), "SV written bank readback");

    std::remove(ksfA.c_str());
    std::remove(ksfB.c_str());
    std::remove(kmpPath.c_str());
    std::remove(wavPath.c_str());
    std::remove(aiffPath.c_str());
    std::remove(bank.c_str());
    ::rmdir(root.c_str());
    std::cout<<"SILVETON Manager core tests PASS\n";
    return 0;
}
