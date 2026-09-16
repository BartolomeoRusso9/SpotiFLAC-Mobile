cmake_minimum_required(VERSION 3.22.1)
project(spotiflac_discord LANGUAGES CXX)

find_package(discord_partner_sdk REQUIRED CONFIG)
add_library(spotiflac_discord SHARED discord_presence.cpp)
target_compile_features(spotiflac_discord PRIVATE cxx_std_20)
target_link_libraries(spotiflac_discord discord_partner_sdk::discord_partner_sdk)
target_link_options(spotiflac_discord PRIVATE "-Wl,-z,max-page-size=16384")
