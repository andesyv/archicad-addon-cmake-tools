if (CMAKE_VERSION VERSION_LESS "3.20.0")
    message (FATAL_ERROR "This script now requires CMake 3.20.0 or newer")
endif ()

function (SetGlobalCompilerDefinitions acVersion)

    if (WIN32)
        add_definitions (-DUNICODE -D_UNICODE -D_ITERATOR_DEBUG_LEVEL=0)
        set (CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL PARENT_SCOPE)
    else ()
        add_definitions (-Dmacintosh=1)
        if (${acVersion} GREATER_EQUAL 26)
            set (CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "" FORCE)
        endif ()
    endif ()
    add_definitions (-DACExtension)

endfunction ()

function (SetCompilerOptions target acVersion)

    if (${acVersion} LESS 27)
        target_compile_features (${target} PUBLIC cxx_std_14)
    else ()
        target_compile_features (${target} PUBLIC cxx_std_17)
    endif ()
    target_compile_options (${target} PUBLIC "$<$<CONFIG:Debug>:-DDEBUG>")
    if (WIN32)
        target_compile_options (${target} PUBLIC /W4 /WX
            /Zc:wchar_t-
            /wd4499
            /EHsc
            -D_CRT_SECURE_NO_WARNINGS
        )
    else ()
        target_compile_options (${target} PUBLIC -Wall -Wextra -Werror
            -fvisibility=hidden
            -Wno-multichar
            -Wno-ctor-dtor-privacy
            -Wno-invalid-offsetof
            -Wno-ignored-qualifiers
            -Wno-reorder
            -Wno-overloaded-virtual
            -Wno-unused-parameter
            -Wno-unused-value
            -Wno-unused-private-field
            -Wno-deprecated
            -Wno-unknown-pragmas
            -Wno-missing-braces
            -Wno-missing-field-initializers
            -Wno-non-c-typedef-for-linkage
            -Wno-uninitialized-const-reference
            -Wno-shorten-64-to-32
            -Wno-sign-compare
            -Wno-switch
        )
        if (${acVersion} LESS_EQUAL "24")
            target_compile_options (${target} PUBLIC -Wno-non-c-typedef-for-linkage)
        endif ()
    endif ()

endfunction ()

function (LinkGSLibrariesToProject target acVersion devKitDir)

    if (WIN32)
        if (${acVersion} LESS 27)
            target_link_libraries (${target}
                "${devKitDir}/Lib/Win/ACAP_STAT.lib"
            )
        else ()
            target_link_libraries (${target}
                "${devKitDir}/Lib/ACAP_STAT.lib"
            )
        endif ()
    else ()
        find_library (CocoaFramework Cocoa)
        if (${acVersion} LESS 27)
            target_link_libraries (${target}
                "${devKitDir}/Lib/Mactel/libACAP_STAT.a"
                ${CocoaFramework}
            )
        else ()
            target_link_libraries (${target}
                "${devKitDir}/Lib/libACAP_STAT.a"
                ${CocoaFramework}
            )
        endif ()
    endif ()

    file (GLOB ModuleFolders ${devKitDir}/Modules/*)
    target_include_directories (${target} SYSTEM PUBLIC ${ModuleFolders})
    if (WIN32)
        file (GLOB LibFilesInFolder ${devKitDir}/Modules/*/*/*.lib)
        target_link_libraries (${target} ${LibFilesInFolder})
    else ()
        file (GLOB LibFilesInFolder
            ${devKitDir}/Frameworks/*.framework
            ${devKitDir}/Frameworks/*.dylib
        )
        target_link_libraries (${target} ${LibFilesInFolder})
    endif ()

endfunction ()

function (add_addon target)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "NAME;DEV_KIT_DIR;AC_VERSION" "")
    if (arg_UNPARSED_ARGUMENTS)
        message (FATAL_ERROR "Unparsed arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif ()

    if (NOT arg_NAME)
        message (FATAL_ERROR "Missing required argument: NAME")
    endif ()

    if (NOT arg_DEV_KIT_DIR)
        message (FATAL_ERROR "Missing required argument: DEV_KIT_DIR")
    endif ()

    if (NOT arg_AC_VERSION)
        message (FATAL_ERROR "Missing required argument: AC_VERSION")
    endif ()

    # Create target
    if (WIN32)
        add_library (${target} SHARED)
    else ()
        add_library (${target} MODULE)
    endif ()

    # Set add-on properties on target
    set_target_properties (${target} PROPERTIES
        OUTPUT_NAME ${arg_NAME}
        DEV_KIT_DIR ${arg_DEV_KIT_DIR}
    )
    if (WIN32)
        set_target_properties (${target} PROPERTIES SUFFIX ".apx")
        set_target_properties (${target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY_$<CONFIG> "${CMAKE_BINARY_DIR}/$<CONFIG>")
        target_link_options (${target} PUBLIC "${ResourceObjectsDir}/${arg_NAME}.res")
        target_link_options (${target} PUBLIC /export:GetExportedFuncAddrs,@1 /export:SetImportedFuncAddrs,@2)
    else ()
        # Prepare various variables for the Info.plist
        string(TOLOWER "${arg_NAME}" lowerAddOnName)
        string(REGEX REPLACE "[ _]" "-" addOnNameIdentifier "${lowerAddOnName}")
        string(TIMESTAMP copyright "Copyright © GRAPHISOFT SE, 1984-%Y")
        # BE on the safe side; load the info from an existing framework
        file(READ "${arg_DEV_KIT_DIR}/Frameworks/GSRoot.framework/Versions/A/Resources/Info.plist" plist_content NEWLINE_CONSUME)
        string(REGEX REPLACE ".*GSBuildNum[^0-9]+([0-9]+).*" "\\1" gsBuildNum "${plist_content}")
        string(REGEX REPLACE ".*LSMinimumSystemVersion[^0-9]+([0-9\.]+).*" "\\1" lsMinimumSystemVersion "${plist_content}")

        set(MACOSX_BUNDLE_EXECUTABLE_NAME ${arg_NAME})
        set(MACOSX_BUNDLE_INFO_STRING ${arg_NAME})
        set(MACOSX_BUNDLE_GUI_IDENTIFIER com.graphisoft.${addOnNameIdentifier})
        set(MACOSX_BUNDLE_LONG_VERSION_STRING ${copyright})
        set(MACOSX_BUNDLE_BUNDLE_NAME ${arg_NAME})
        set(MACOSX_BUNDLE_SHORT_VERSION_STRING ${arg_AC_VERSION}.0.0.${gsBuildNum})
        set(MACOSX_BUNDLE_BUNDLE_VERSION ${arg_AC_VERSION}.0.0.${gsBuildNum})
        set(MACOSX_BUNDLE_COPYRIGHT ${copyright})
        set(MINIMUM_SYSTEM_VERSION "${lsMinimumSystemVersion}")

        # Configure the Info.plist file
        configure_file(
            "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/AddOnInfo.plist.in"
            "${CMAKE_BINARY_DIR}/AddOnInfo.plist"
            @ONLY
        )
        set_target_properties(${target} PROPERTIES
            BUNDLE TRUE
            MACOSX_BUNDLE_INFO_PLIST "${CMAKE_BINARY_DIR}/AddOnInfo.plist"

            # Align parameters for Xcode and in Info.plist to avoid warnings
            XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER com.graphisoft.${addOnNameIdentifier}
            XCODE_ATTRIBUTE_MACOSX_DEPLOYMENT_TARGET ${lsMinimumSystemVersion}

            LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>"
        )
    endif ()

    target_include_directories (${target} SYSTEM PUBLIC ${arg_DEV_KIT_DIR}/Inc)

    # use GSRoot custom allocators consistently in the Add-On
    get_filename_component(new_hpp "${arg_DEV_KIT_DIR}/Modules/GSRoot/GSNew.hpp" REALPATH)
    get_filename_component(malloc_hpp "${arg_DEV_KIT_DIR}/Modules/GSRoot/GSMalloc.hpp" REALPATH)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        target_compile_options(
            "${target}" PRIVATE
            "SHELL:/FI \"${new_hpp}\""
            "SHELL:/FI \"${malloc_hpp}\""
        )
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang\$")
        target_compile_options(
            "${target}" PRIVATE
            "SHELL:-include \"${new_hpp}\""
            "SHELL:-include \"${malloc_hpp}\""
        )
    else()
        message(FATAL_ERROR "Unknown compiler ID. Please open an issue at https://github.com/GRAPHISOFT/archicad-addon-cmake-tools")
    endif()

    LinkGSLibrariesToProject (${target} ${arg_AC_VERSION} ${arg_DEV_KIT_DIR})

    SetCompilerOptions (${target} ${arg_AC_VERSION})
endfunction ()

function (target_addon_resources target)
    cmake_parse_arguments(PARSE_ARGV 1 arg "" "RESOURCE_ROOT_DIR;SOURCES_ROOT_DIR;LANGUAGE_CODE;CONFIG_FILE" "")
    if (arg_UNPARSED_ARGUMENTS)
        message (FATAL_ERROR "Unparsed arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif ()

    if (NOT arg_CONFIG_FILE)
        set (arg_CONFIG_FILE ${CMAKE_SOURCE_DIR}/config.json)
    endif ()

    if (NOT arg_LANGUAGE_CODE)
        # Read default language from config.json
        file (READ ${arg_CONFIG_FILE} configs_content)
        string (JSON AC_ADDON_DEFAULT_LANGUAGE GET "${configs_content}" "defaultLanguage")
        if ("${AC_ADDON_DEFAULT_LANGUAGE}" STREQUAL "")
            message (FATAL_ERROR "Default language is not set in ${arg_CONFIG_FILE}")
        endif ()
        set (arg_LANGUAGE_CODE ${AC_ADDON_DEFAULT_LANGUAGE})
        message (STATUS "Using detected language: ${arg_LANGUAGE_CODE}")
    else ()
        check_valid_language_code (${arg_CONFIG_FILE} ${arg_LANGUAGE_CODE})
    endif ()

    if (NOT arg_RESOURCE_ROOT_DIR)
        set (arg_RESOURCE_ROOT_DIR ${CMAKE_CURRENT_SOURCE_DIR})
    elseif ("${arg_RESOURCE_ROOT_DIR}" STREQUAL "")
        message (FATAL_ERROR "Supplied RESOURCE_ROOT_DIR argument is empty")
    endif ()

    cmake_path (ABSOLUTE_PATH arg_RESOURCE_ROOT_DIR NORMALIZE)

    if (NOT TARGET ${target})
        message (FATAL_ERROR "Target ${target} has not beed created yet. Call add_addon (${target}) before calling this fucntion.")
    endif ()

    get_target_property (output_name ${target} OUTPUT_NAME)
    if ("${output_name}" STREQUAL "")
        message (FATAL_ERROR "Target ${target} is missing the OUTPUT_NAME property. This is required for resource compilation.")
    endif ()
    get_target_property (det_kit_dir ${target} DEV_KIT_DIR)
    if ("${det_kit_dir}" STREQUAL "")
        message (FATAL_ERROR "Target ${target} is missing the DEV_KIT_DIR property. This is required for resource compilation.")
    endif ()

    find_package (Python COMPONENTS Interpreter)

    # Setup resource compilation outputs
    set (ResourceObjectsDir ${CMAKE_BINARY_DIR}/ResourceObjects)
    set (ResourceStampFile "${ResourceObjectsDir}/AddOnResources.stamp")

    # Locate resources and add build dependencies
    file (GLOB AddOnImageFiles CONFIGURE_DEPENDS
        ${arg_RESOURCE_ROOT_DIR}/RFIX/Images/*.svg
    )
    if (WIN32)
        file (GLOB AddOnResourceFiles CONFIGURE_DEPENDS
            ${arg_RESOURCE_ROOT_DIR}/R${arg_LANGUAGE_CODE}/*.grc
            ${arg_RESOURCE_ROOT_DIR}/RFIX/*.grc
            ${arg_RESOURCE_ROOT_DIR}/RFIX.win/*.rc2
        )
    else ()
        file (GLOB AddOnResourceFiles CONFIGURE_DEPENDS
            ${arg_RESOURCE_ROOT_DIR}/R${arg_LANGUAGE_CODE}/*.grc
            ${arg_RESOURCE_ROOT_DIR}/RFIX/*.grc
            ${arg_RESOURCE_ROOT_DIR}/RFIX.mac/*.plist
        )
    endif ()

    if ("${arg_SOURCES_ROOT_DIR}" STREQUAL "" OR NOT EXISTS "${arg_SOURCES_ROOT_DIR}")
        # Sources can reside in multiple different folders, so there's no 1 folder this can resolve to. The exception is probably the parent
        # "project" folder which is at least a good guess for a source folder.
        set (arg_SOURCES_ROOT_DIR ${CMAKE_CURRENT_SOURCE_DIR})
    else ()
        cmake_path (ABSOLUTE_PATH arg_SOURCES_ROOT_DIR NORMALIZE)
    endif ()

    if (WIN32)
        add_custom_command (
            OUTPUT ${ResourceStampFile}
            DEPENDS ${AddOnResourceFiles} ${AddOnImageFiles}
            COMMENT "Compiling resources..."
            COMMAND ${CMAKE_COMMAND} -E make_directory "${ResourceObjectsDir}"
            COMMAND ${Python_EXECUTABLE} "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CompileResources.py" "${arg_LANGUAGE_CODE}" "${det_kit_dir}" "${arg_SOURCES_ROOT_DIR}" "${arg_RESOURCE_ROOT_DIR}" "${ResourceObjectsDir}" "${ResourceObjectsDir}/${output_name}.res"
            COMMAND ${CMAKE_COMMAND} -E touch ${ResourceStampFile}
        )
    else ()
        add_custom_command (
            OUTPUT ${ResourceStampFile}
            DEPENDS ${AddOnResourceFiles} ${AddOnImageFiles}
            COMMENT "Compiling resources..."
            COMMAND ${CMAKE_COMMAND} -E make_directory "${ResourceObjectsDir}"
            COMMAND ${Python_EXECUTABLE} "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CompileResources.py" "${arg_LANGUAGE_CODE}" "${det_kit_dir}" "${arg_SOURCES_ROOT_DIR}" "${arg_RESOURCE_ROOT_DIR}" "${ResourceObjectsDir}" "${CMAKE_BINARY_DIR}/$<CONFIG>/${output_name}.bundle/Contents/Resources"
            COMMAND ${CMAKE_COMMAND} -E copy "${det_kit_dir}/Inc/PkgInfo" "${CMAKE_BINARY_DIR}/$<CONFIG>/${output_name}.bundle/Contents/PkgInfo"
            COMMAND ${CMAKE_COMMAND} -E touch ${ResourceStampFile}
        )
    endif ()

    target_sources (${target} PRIVATE
        ${AddOnImageFiles}
        ${AddOnResourceFiles}
        ${ResourceStampFile}
    )

    # Set IDE (generator) options
    source_group ("Images" FILES ${AddOnImageFiles})
    source_group ("Resources" FILES ${AddOnResourceFiles})
endfunction ()

function (GenerateAddOnProject target acVersion devKitDir addOnName addOnSourcesFolder addOnResourcesFolder addOnLanguage)

    add_addon (${target}
        NAME ${addOnName}
        DEV_KIT_DIR ${devKitDir}
        AC_VERSION ${acVersion}
    )

    target_addon_resources (${target}
        NAME ${addOnName}
        DEV_KIT_DIR ${devKitDir}
        RESOURCE_ROOT_DIR ${addOnResourcesFolder}
        SOURCES_ROOT_DIR ${addOnSourcesFolder}
        LANGUAGE_CODE ${addOnLanguage}
    )

    file (GLOB_RECURSE AddOnHeaderFiles CONFIGURE_DEPENDS
        ${addOnSourcesFolder}/*.h
        ${addOnSourcesFolder}/*.hpp
    )
    file (GLOB_RECURSE AddOnSourceFiles CONFIGURE_DEPENDS
        ${addOnSourcesFolder}/*.c
        ${addOnSourcesFolder}/*.cpp
    )

    source_group ("Sources" FILES ${AddOnHeaderFiles} ${AddOnSourceFiles})

    target_sources (${target} PRIVATE
        ${AddOnHeaderFiles}
        ${AddOnSourceFiles}
    )

    target_include_directories (${target} PUBLIC ${addOnSourcesFolder})

    set_source_files_properties (${AddOnSourceFiles} PROPERTIES LANGUAGE CXX)
endfunction ()

function (check_valid_language_code configFile languageCode)
    file (READ ${configFile} configsContent)
    string (JSON configuredLanguagesList GET "${configsContent}" "languages")
    string (JSON configuredLanguagesListLen LENGTH "${configsContent}" "languages")
    set (i 0)
    while (${i} LESS ${configuredLanguagesListLen})
        string (JSON language GET "${configuredLanguagesList}" ${i})
        if (${language} STREQUAL ${languageCode})
            return ()
        endif ()
        math (EXPR i "${i} + 1")
    endwhile()

    message (FATAL_ERROR "Language code ${languageCode} is not part of the configured languages in ${configFile}.")
endfunction ()

function (verify_api_devkit_folder devKitPath)
    if (NOT EXISTS ${devKitPath})
        message (FATAL_ERROR "The supplied API DevKit path ${devKitPath} does not exist")
    endif ()

    cmake_path (GET devKitPath FILENAME currentFolderName)
    if (NOT "${currentFolderName}" STREQUAL "Support")
        message (FATAL_ERROR "The supplied API DevKit path should point to the /Support subfolder of the API DevKit. Actual path: ${devKitPath}")
    endif ()

    if (NOT EXISTS "${devKitPath}/Lib")
        message (FATAL_ERROR "${devKitPath}/Lib does not exist")
    endif ()

    if (NOT EXISTS "${devKitPath}/Modules")
        message (FATAL_ERROR "${devKitPath}/Modules does not exist")
    endif ()

    if (APPLE AND NOT EXISTS "${devKitPath}/Frameworks")
        message (FATAL_ERROR "${devKitPath}/Frameworks does not exist")
    endif ()
endfunction ()
