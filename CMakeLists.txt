cmake_minimum_required(VERSION 3.20)

project(SILVETON_MANAGER VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(APPLE)
    enable_language(OBJCXX)
    set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "SILVETON Manager target architecture" FORCE)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13" CACHE STRING "Minimum supported macOS version" FORCE)
endif()

option(SILVETON_MANAGER_BUILD_TESTS "Build SILVETON Manager tests" ON)

set(SILVETON_MANAGER_CORE_SOURCES
    src/core/AudioFileLoader.cpp
    src/core/KorgImporter.cpp
    src/core/MediaPathPolicy.cpp
    src/core/ObjectManager.cpp
    src/core/SampleEditor.cpp
    src/core/SampleEditorRegions.cpp
    src/core/SoundEditor.cpp
    src/core/SvBankBuilder.cpp
    src/core/SvBankFormat.cpp
    src/core/SvBankReader.cpp
    src/core/SampleHash.cpp
)

add_library(silveton_manager_core STATIC ${SILVETON_MANAGER_CORE_SOURCES})

target_include_directories(silveton_manager_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(silveton_manager_core PUBLIC cxx_std_17)

if(CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang|GNU")
    target_compile_options(silveton_manager_core PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        -Wshadow
        -Wconversion
        -Werror
    )
endif()

if(APPLE)
    add_executable(SILVETON_MANAGER MACOSX_BUNDLE
        src/app/main.mm
        src/app/AppDelegate.mm
        src/app/BankFileCommands.mm
        src/app/MediaController.mm
        src/app/ObjectManagerController.mm
        src/app/MainWindowController.mm
        src/app/WaveformInteraction.mm
        src/app/SampleAuditionPlayer.mm
        src/app/MultisampleEditorController.mm
        src/app/BankOrganizerController.mm
        src/app/SoundEditorController.mm
        src/app/ManagerDocument.mm
        src/app/ManagerDocumentBankIO.mm
        src/app/ManagerDocumentObjects.mm
    )

    target_link_libraries(SILVETON_MANAGER PRIVATE
        silveton_manager_core
        "-framework AppKit"
        "-framework Foundation"
        "-framework CoreFoundation"
        "-framework AudioToolbox"
    )

    target_compile_options(SILVETON_MANAGER PRIVATE -fobjc-arc)

    set_target_properties(SILVETON_MANAGER PROPERTIES
        OUTPUT_NAME "SILVETON Manager"
        MACOSX_BUNDLE_BUNDLE_NAME "SILVETON Manager"
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.silveton.manager"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_BUNDLE_VERSION "1"
    )
endif()

if(SILVETON_MANAGER_BUILD_TESTS)
    enable_testing()

    add_executable(silveton_manager_tests
        tests/ManagerCoreTests.cpp
    )
    add_executable(silveton_sample_editor_region_tests
        tests/SampleEditorRegionTests.cpp
    )
    add_executable(silveton_sound_editor_tests
        tests/SoundEditorTests.cpp
    )
    add_executable(silveton_media_path_tests
        tests/MediaPathPolicyTests.cpp
    )
    add_executable(silveton_object_manager_tests
        tests/ObjectManagerTests.cpp
    )

    target_link_libraries(silveton_manager_tests PRIVATE silveton_manager_core)
    target_link_libraries(silveton_sample_editor_region_tests PRIVATE silveton_manager_core)
    target_link_libraries(silveton_sound_editor_tests PRIVATE silveton_manager_core)
    target_link_libraries(silveton_media_path_tests PRIVATE silveton_manager_core)
    target_link_libraries(silveton_object_manager_tests PRIVATE silveton_manager_core)

    if(CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang|GNU")
        target_compile_options(silveton_manager_tests PRIVATE
            -Wall
            -Wextra
            -Wpedantic
            -Wshadow
            -Wconversion
            -Werror
        )
        target_compile_options(silveton_sample_editor_region_tests PRIVATE
            -Wall
            -Wextra
            -Wpedantic
            -Wshadow
            -Wconversion
            -Werror
        )
        target_compile_options(silveton_sound_editor_tests PRIVATE
            -Wall
            -Wextra
            -Wpedantic
            -Wshadow
            -Wconversion
            -Werror
        )
        target_compile_options(silveton_media_path_tests PRIVATE
            -Wall
            -Wextra
            -Wpedantic
            -Wshadow
            -Wconversion
            -Werror
        )
        target_compile_options(silveton_object_manager_tests PRIVATE
            -Wall
            -Wextra
            -Wpedantic
            -Wshadow
            -Wconversion
            -Werror
        )
    endif()

    add_test(NAME silveton_manager_core COMMAND silveton_manager_tests)
    add_test(NAME silveton_sample_editor_regions COMMAND silveton_sample_editor_region_tests)
    add_test(NAME silveton_sound_editor COMMAND silveton_sound_editor_tests)
    add_test(NAME silveton_media_paths COMMAND silveton_media_path_tests)
    add_test(NAME silveton_object_manager COMMAND silveton_object_manager_tests)

    set(SILVETON_MANAGER_TEST_TARGETS
        silveton_manager_tests
        silveton_sample_editor_region_tests
        silveton_sound_editor_tests
        silveton_media_path_tests
        silveton_object_manager_tests
    )

    if(APPLE)
        add_executable(silveton_manager_bank_io_tests
            tests/ManagerDocumentBankIOTests.mm
            src/app/ManagerDocument.mm
            src/app/ManagerDocumentBankIO.mm
        )
        target_link_libraries(silveton_manager_bank_io_tests PRIVATE
            silveton_manager_core
            "-framework Foundation"
        )
        target_compile_options(silveton_manager_bank_io_tests PRIVATE -fobjc-arc)
        add_test(NAME silveton_manager_bank_io COMMAND silveton_manager_bank_io_tests)
        list(APPEND SILVETON_MANAGER_TEST_TARGETS silveton_manager_bank_io_tests)
    endif()

    # One target builds every test executable first and then runs the complete
    # registered CTest suite exactly once. CI only needs to invoke this target.
    add_custom_target(silveton_manager_check
        COMMAND ${CMAKE_CTEST_COMMAND}
                --test-dir "${CMAKE_BINARY_DIR}"
                -C "$<CONFIG>"
                --output-on-failure
        DEPENDS ${SILVETON_MANAGER_TEST_TARGETS}
        USES_TERMINAL
        VERBATIM
    )
endif()
