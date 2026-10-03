#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include <algorithm>
#include <cstdint>
#include <cstring>

@interface SVSampleAuditionPlayer : NSObject
- (BOOL)playState:(NSDictionary<NSString*, id>*)state loopOnly:(BOOL)loopOnly error:(NSString**)error;
- (void)stop;
@end

@implementation SVSampleAuditionPlayer {
    AudioQueueRef _queue;
    NSData* _audioData;
    UInt32 _bytesPerFrame;
    UInt64 _cursorFrame;
    UInt64 _startFrame;
    UInt64 _endFrame;
    BOOL _repeat;
    BOOL _stopping;
}

static void SVAudioQueueOutputCallback(void* userData, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    SVSampleAuditionPlayer* player = (__bridge SVSampleAuditionPlayer*)userData;
    [player fillBufferForQueue:queue buffer:buffer];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = nullptr;
        _audioData = nil;
        _bytesPerFrame = 0U;
        _cursorFrame = 0U;
        _startFrame = 0U;
        _endFrame = 0U;
        _repeat = NO;
        _stopping = NO;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)setError:(NSString**)error format:(NSString*)format status:(OSStatus)status {
    if (error != nullptr) {
        *error = [NSString stringWithFormat:format, static_cast<long>(status)];
    }
}

- (BOOL)playState:(NSDictionary<NSString*, id>*)state loopOnly:(BOOL)loopOnly error:(NSString**)error {
    [self stop];

    NSData* audio = state[@"audioData"];
    const UInt32 sampleRate = [state[@"sampleRate"] unsignedIntValue];
    const UInt32 channels = [state[@"channels"] unsignedIntValue];
    const UInt32 encoding = [state[@"encoding"] unsignedIntValue];
    const UInt32 bitsPerSample = [state[@"bitsPerSample"] unsignedIntValue];
    const UInt64 totalFrames = [state[@"totalFrames"] unsignedLongLongValue];
    const BOOL loopEnabled = [state[@"loopEnabled"] boolValue];
    const UInt64 loopStart = [state[@"loopStart"] unsignedLongLongValue];
    const UInt64 loopEnd = [state[@"loopEnd"] unsignedLongLongValue];

    if (![audio isKindOfClass:[NSData class]] || audio.length == 0U || sampleRate == 0U || channels == 0U || channels > 2U || totalFrames == 0U) {
        if (error != nullptr) *error = @"The selected sample cannot be auditioned because its audio format is invalid.";
        return NO;
    }

    UInt32 bytesPerSample = 0U;
    AudioFormatFlags flags = kAudioFormatFlagIsPacked;
    switch (encoding) {
        case 1U:
            bytesPerSample = 2U;
            flags |= kAudioFormatFlagIsSignedInteger;
            break;
        case 2U:
            bytesPerSample = 3U;
            flags |= kAudioFormatFlagIsSignedInteger;
            break;
        case 3U:
            bytesPerSample = 4U;
            flags |= kAudioFormatFlagIsFloat;
            break;
        default:
            if (error != nullptr) *error = @"The selected sample uses an unsupported audition encoding.";
            return NO;
    }

    const UInt32 expectedBits = bytesPerSample * 8U;
    if (bitsPerSample != 0U && bitsPerSample != expectedBits) {
        if (error != nullptr) *error = @"The sample bit depth does not match its stored PCM encoding.";
        return NO;
    }

    const UInt64 calculatedBytes = totalFrames * static_cast<UInt64>(channels) * static_cast<UInt64>(bytesPerSample);
    if (calculatedBytes != static_cast<UInt64>(audio.length)) {
        if (error != nullptr) *error = @"The sample audio payload length does not match its frame count.";
        return NO;
    }

    UInt64 startFrame = 0U;
    UInt64 endFrame = totalFrames;
    BOOL repeat = NO;
    if (loopOnly) {
        if (!loopEnabled || loopStart >= loopEnd || loopEnd > totalFrames) {
            if (error != nullptr) *error = @"This sample has no valid enabled loop to audition.";
            return NO;
        }
        startFrame = loopStart;
        endFrame = loopEnd;
        repeat = YES;
    }

    AudioStreamBasicDescription format{};
    format.mSampleRate = static_cast<Float64>(sampleRate);
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = flags;
    format.mBytesPerPacket = bytesPerSample * channels;
    format.mFramesPerPacket = 1U;
    format.mBytesPerFrame = bytesPerSample * channels;
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = expectedBits;

    AudioQueueRef queue = nullptr;
    const OSStatus createStatus = AudioQueueNewOutput(&format,
                                                      SVAudioQueueOutputCallback,
                                                      (__bridge void*)self,
                                                      nullptr,
                                                      nullptr,
                                                      0U,
                                                      &queue);
    if (createStatus != noErr || queue == nullptr) {
        [self setError:error format:@"AudioQueue could not open the output device (OSStatus %ld)." status:createStatus];
        return NO;
    }

    @synchronized (self) {
        _queue = queue;
        _audioData = audio;
        _bytesPerFrame = format.mBytesPerFrame;
        _startFrame = startFrame;
        _endFrame = endFrame;
        _cursorFrame = startFrame;
        _repeat = repeat;
        _stopping = NO;
    }

    UInt32 requestedBufferBytes = 65536U;
    requestedBufferBytes -= requestedBufferBytes % _bytesPerFrame;
    requestedBufferBytes = std::max(requestedBufferBytes, _bytesPerFrame * 256U);

    for (UInt32 index = 0U; index < 3U; ++index) {
        AudioQueueBufferRef buffer = nullptr;
        const OSStatus allocateStatus = AudioQueueAllocateBuffer(queue, requestedBufferBytes, &buffer);
        if (allocateStatus != noErr || buffer == nullptr) {
            [self stop];
            [self setError:error format:@"AudioQueue could not allocate a playback buffer (OSStatus %ld)." status:allocateStatus];
            return NO;
        }
        [self fillBufferForQueue:queue buffer:buffer];
    }

    const OSStatus startStatus = AudioQueueStart(queue, nullptr);
    if (startStatus != noErr) {
        [self stop];
        [self setError:error format:@"AudioQueue could not start playback (OSStatus %ld)." status:startStatus];
        return NO;
    }

    if (error != nullptr) *error = nil;
    return YES;
}

- (void)fillBufferForQueue:(AudioQueueRef)queue buffer:(AudioQueueBufferRef)buffer {
    if (queue == nullptr || buffer == nullptr) return;

    @synchronized (self) {
        if (_queue != queue || _stopping || _audioData == nil || _bytesPerFrame == 0U) return;

        UInt32 capacityFrames = buffer->mAudioDataBytesCapacity / _bytesPerFrame;
        UInt32 writtenFrames = 0U;
        std::uint8_t* destination = static_cast<std::uint8_t*>(buffer->mAudioData);
        const std::uint8_t* source = static_cast<const std::uint8_t*>(_audioData.bytes);

        while (capacityFrames > 0U) {
            if (_cursorFrame >= _endFrame) {
                if (_repeat) _cursorFrame = _startFrame;
                else break;
            }

            const UInt64 availableFrames64 = _endFrame - _cursorFrame;
            const UInt32 availableFrames = availableFrames64 > static_cast<UInt64>(UINT32_MAX)
                ? UINT32_MAX
                : static_cast<UInt32>(availableFrames64);
            const UInt32 framesToCopy = std::min(capacityFrames, availableFrames);
            if (framesToCopy == 0U) break;

            const UInt64 byteOffset64 = _cursorFrame * static_cast<UInt64>(_bytesPerFrame);
            const UInt32 bytesToCopy = framesToCopy * _bytesPerFrame;
            std::memcpy(destination + static_cast<std::size_t>(writtenFrames) * _bytesPerFrame,
                        source + static_cast<std::size_t>(byteOffset64),
                        bytesToCopy);
            _cursorFrame += framesToCopy;
            writtenFrames += framesToCopy;
            capacityFrames -= framesToCopy;
        }

        buffer->mAudioDataByteSize = writtenFrames * _bytesPerFrame;
        if (buffer->mAudioDataByteSize > 0U) {
            AudioQueueEnqueueBuffer(queue, buffer, 0U, nullptr);
        }
    }
}

- (void)stop {
    AudioQueueRef queue = nullptr;
    @synchronized (self) {
        if (_queue == nullptr) {
            _audioData = nil;
            return;
        }
        _stopping = YES;
        queue = _queue;
        _queue = nullptr;
    }

    AudioQueueStop(queue, true);
    AudioQueueDispose(queue, true);

    @synchronized (self) {
        _audioData = nil;
        _bytesPerFrame = 0U;
        _cursorFrame = 0U;
        _startFrame = 0U;
        _endFrame = 0U;
        _repeat = NO;
        _stopping = NO;
    }
}

@end
