# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file LICENSE.rst or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION ${CMAKE_VERSION}) # this file comes with cmake

# If CMAKE_DISABLE_SOURCE_CHANGES is set to true and the source directory is an
# existing directory in our source tree, calling file(MAKE_DIRECTORY) on it
# would cause a fatal error, even though it would be a no-op.
if(NOT EXISTS "C:/SIH/firmware/app")
  file(MAKE_DIRECTORY "C:/SIH/firmware/app")
endif()
file(MAKE_DIRECTORY
  "C:/SIH/build/app"
  "C:/SIH/build/_sysbuild/sysbuild/images/app-prefix"
  "C:/SIH/build/_sysbuild/sysbuild/images/app-prefix/tmp"
  "C:/SIH/build/_sysbuild/sysbuild/images/app-prefix/src/app-stamp"
  "C:/SIH/build/_sysbuild/sysbuild/images/app-prefix/src"
  "C:/SIH/build/_sysbuild/sysbuild/images/app-prefix/src/app-stamp"
)

set(configSubDirs )
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "C:/SIH/build/_sysbuild/sysbuild/images/app-prefix/src/app-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "C:/SIH/build/_sysbuild/sysbuild/images/app-prefix/src/app-stamp${cfgdir}") # cfgdir has leading slash
endif()
