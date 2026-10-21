#include "../native/app/src/main/cpp/vits_prosody.hpp"
#include <cassert>
#include <iostream>
#include <numeric>

int main() {
    using namespace memo_prosody;
    std::vector<int> ids{0, 22, 0, 1, 0, 23, 0}, kinds{0, 0, 0, 2, 0, 0, 0};
    std::vector<float> frames{4, 10, 20, 30, 20, 11, 5};
    auto original = frames;
    legacy_cap_pauses(frames, ids, kinds, .8f);
    assert(frames[0] == original[0] && frames[1] == original[1]);
    assert(frames[5] == original[5] && frames[6] == original[6]);
    assert(frames[2] + frames[3] + frames[4] <= pause_budget(2, .8f));
    assert(frames[2] >= 1 && frames[3] >= 1 && frames[4] >= 1);
    auto withoutPunctuation = original;
    legacy_cap_pauses(withoutPunctuation, ids, std::vector<int>(7, 0), .8f);
    assert(withoutPunctuation == original); // Spaces / structural blanks inside words are untouched.
    auto shortPause = std::vector<float>{2, 10, 1, 2, 1, 11, 3};
    auto shortOriginal = shortPause;
    legacy_cap_pauses(shortPause, ids, kinds, .8f);
    assert(shortPause == shortOriginal); // A cap never lengthens an already natural pause.
    assert(pause_budget(1, 1.f) < pause_budget(2, 1.f));
    assert(pause_budget(2, 1.f) < pause_budget(3, 1.f));
    assert(pause_budget(3, 1.f) < pause_budget(4, 1.f));
    assert(pause_budget(2, .5f) > pause_budget(2, 1.f));
    std::vector<int> repeated{0, 22, 0, 1, 0, 2, 0, 23, 0}, types{0, 0, 0, 1, 0, 3, 0, 0, 0};
    std::vector<float> group{2, 10, 20, 30, 20, 30, 20, 11, 3};
    legacy_cap_pauses(group, repeated, types, 1.f);
    assert(std::accumulate(group.begin() + 2, group.begin() + 7, 0.f) <= pause_budget(3, 1.f));
    assert(group[1] == 10 && group[7] == 11);
    bool rejected = false;
    try { legacy_cap_pauses(group, ids, kinds, 1.f); } catch (const std::invalid_argument&) { rejected = true; }
    assert(rejected);
    // The old cap missed the literal space that G2P inserts after punctuation.
    std::vector<int> spaced{0, 22, 0, 1, 0, 51, 0, 23, 0, 51, 0, 24, 0};
    std::vector<int> comma{0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    std::vector<float> longGap{2, 10, 2, 2, 2, 60, 2, 11, 3, 9, 4, 12, 2};
    auto untouched = longGap;
    constrain_pauses(longGap, spaced, comma, .8f);
    assert(std::accumulate(longGap.begin() + 2, longGap.begin() + 7, 0.f) <= pause_budget(2, .8f));
    for (size_t i : {0u, 1u, 7u, 8u, 9u, 10u, 11u, 12u}) assert(longGap[i] == untouched[i]);
    auto sentence = comma; sentence[3] = 3;
    auto tiny = std::vector<float>{2, 10, 1, 1, 1, 1, 1, 11, 3, 9, 4, 12, 2};
    auto tinyOriginal = tiny;
    constrain_pauses(tiny, spaced, sentence, .8f);
    assert(std::accumulate(tiny.begin() + 2, tiny.begin() + 7, 0.f) >= pause_floor(3, .8f));
    assert(pause_floor(3, .8f) > pause_budget(2, .8f));
    assert(tiny[1] == tinyOriginal[1] && tiny[7] == tinyOriginal[7] && tiny[9] == tinyOriginal[9]);
    auto zero = std::vector<float>(spaced.size(), 0);
    constrain_pauses(zero, spaced, sentence, .8f);
    assert(zero[3] >= pause_floor(3, .8f));
    auto cluster = std::vector<float>{1,10,1,1,1,1,1,11,1};
    constrain_pauses(cluster, repeated, types, .8f);
    assert(std::accumulate(cluster.begin()+2, cluster.begin()+7, 0.f) >= pause_floor(3, .8f));
    std::cout << "PASS: punctuation-only duration budgets, connected clusters, slow-rate allowance, speech preservation and metadata validation\n";
}
