#include "../native/app/src/main/cpp/vits_prosody.hpp"
#include <cassert>
#include <iostream>
#include <numeric>

int main() {
    using namespace memo_prosody;
    std::vector<int> ids{0, 22, 0, 1, 0, 23, 0}, kinds{0, 0, 0, 2, 0, 0, 0};
    std::vector<float> frames{4, 10, 20, 30, 20, 11, 5};
    auto original = frames;
    constrain_pauses(frames, ids, kinds, .8f);
    assert(frames[0] == original[0] && frames[1] == original[1]);
    assert(frames[5] == original[5] && frames[6] == original[6]);
    assert(frames[2] + frames[3] + frames[4] <= pause_budget(2, .8f));
    assert(frames[2] >= 1 && frames[3] >= 1 && frames[4] >= 1);
    auto withoutPunctuation = original;
    constrain_pauses(withoutPunctuation, ids, std::vector<int>(7, 0), .8f);
    assert(withoutPunctuation == original); // Spaces / structural blanks inside words are untouched.
    auto shortPause = std::vector<float>{2, 10, 1, 2, 1, 11, 3};
    auto shortOriginal = shortPause;
    constrain_pauses(shortPause, ids, kinds, .8f);
    assert(shortPause == shortOriginal); // A cap never lengthens an already natural pause.
    assert(pause_budget(1, 1.f) < pause_budget(2, 1.f));
    assert(pause_budget(2, 1.f) < pause_budget(3, 1.f));
    assert(pause_budget(3, 1.f) < pause_budget(4, 1.f));
    assert(pause_budget(2, .5f) > pause_budget(2, 1.f));
    std::vector<int> repeated{0, 22, 0, 1, 0, 2, 0, 23, 0}, types{0, 0, 0, 1, 0, 3, 0, 0, 0};
    std::vector<float> group{2, 10, 20, 30, 20, 30, 20, 11, 3};
    constrain_pauses(group, repeated, types, 1.f);
    assert(std::accumulate(group.begin() + 2, group.begin() + 7, 0.f) <= pause_budget(3, 1.f));
    assert(group[1] == 10 && group[7] == 11);
    bool rejected = false;
    try { constrain_pauses(group, ids, kinds, 1.f); } catch (const std::invalid_argument&) { rejected = true; }
    assert(rejected);
    std::cout << "PASS: punctuation-only duration budgets, connected clusters, slow-rate allowance, speech preservation and metadata validation\n";
}
