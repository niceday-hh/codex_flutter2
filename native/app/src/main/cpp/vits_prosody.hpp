#pragma once
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <vector>

namespace memo_prosody {
// Budgets are local to punctuation and its adjacent structural blanks, never word blanks.
inline int pause_budget(int kind, float rate) {
    const double seconds[] = {0., .14, .26, .46, .65};
    if (kind < 1 || kind > 4 || !std::isfinite(rate) || rate < .5f || rate > 1.3f)
        throw std::invalid_argument("Invalid pause policy");
    return static_cast<int>(std::ceil(seconds[kind] * 22050. / 256. / std::sqrt(rate)));
}
inline void legacy_cap_pauses(std::vector<float>& frames, const std::vector<int>& ids,
                            const std::vector<int>& kinds, float rate) {
    if (frames.size() != ids.size() || ids.size() != kinds.size()) throw std::invalid_argument("Pause metadata mismatch");
    for (size_t p = 0; p < ids.size();) {
        if (!kinds[p]) { ++p; continue; }
        size_t first = p > 0 && ids[p - 1] == 0 ? p - 1 : p;
        size_t last = p; int kind = kinds[p];
        while (last + 1 < ids.size() && (ids[last + 1] == 0 || kinds[last + 1])) {
            ++last; kind = std::max(kind, kinds[last]);
        }
        float total = 0; int positive = 0;
        for (size_t k = first; k <= last; ++k) {
            if (!std::isfinite(frames[k]) || frames[k] < 0) throw std::invalid_argument("Invalid predicted frames");
            total += frames[k]; positive += frames[k] > 0;
        }
        int cap = std::max(pause_budget(kind, rate), positive);
        if (total > cap) {
            int sum = 0;
            for (size_t k = first; k <= last; ++k) {
                frames[k] = frames[k] > 0 ? std::max(1.f, std::floor(frames[k] * cap / total)) : 0;
                sum += static_cast<int>(frames[k]);
            }
            while (sum > cap) {
                auto largest = std::max_element(frames.begin() + first, frames.begin() + last + 1);
                if (*largest <= 1) break;
                --*largest; --sum;
            }
        }
        p = last + 1;
    }
}
// Model symbol 51 is a word-space. Only spaces touching punctuation belong
// to this group; ordinary spaces between two spoken words remain unchanged.
inline bool separator(int id) { return id == 0 || id == 51; }
inline int pause_floor(int kind, float rate) {
    pause_budget(kind, rate); // Validate rate/kind before arithmetic.
    const double seconds[] = {0., 0., 0., .32, .46};
    return static_cast<int>(std::ceil(seconds[kind] * 22050. / 256. / std::sqrt(rate)));
}
inline void constrain_pauses(std::vector<float>& frames, const std::vector<int>& ids,
                            const std::vector<int>& kinds, float rate) {
    if (frames.size() != ids.size() || ids.size() != kinds.size()) throw std::invalid_argument("Pause metadata mismatch");
    for (size_t p = 0; p < ids.size();) {
        if (!kinds[p]) { ++p; continue; }
        size_t first = p, last = p; int kind = kinds[p];
        while (first > 0 && separator(ids[first - 1])) --first;
        while (last + 1 < ids.size() && (separator(ids[last + 1]) || kinds[last + 1])) {
            ++last; kind = std::max(kind, kinds[last]);
        }
        double total = 0; int positive = 0;
        for (size_t k = first; k <= last; ++k) {
            if (!std::isfinite(frames[k]) || frames[k] < 0) throw std::invalid_argument("Invalid predicted frames");
            total += frames[k]; positive += frames[k] > 0;
        }
        const int floor = pause_floor(kind, rate), cap = std::max(pause_budget(kind, rate), positive);
        if (total > cap || total < floor) {
            const int target = total > cap ? cap : floor;
            if (total == 0) frames[p] = static_cast<float>(target);
            else {
                int sum = 0;
                for (size_t k = first; k <= last; ++k) {
                    frames[k] = frames[k] > 0 ? std::max(1.f, static_cast<float>(std::floor(frames[k] * target / total))) : 0;
                    sum += static_cast<int>(frames[k]);
                }
                while (sum > target) {
                    auto largest = std::max_element(frames.begin() + first, frames.begin() + last + 1);
                    if (*largest <= 1) break;
                    --*largest; --sum;
                }
                // Rounding remainder belongs to the strongest predicted pause component.
                if (sum < target) *std::max_element(frames.begin() + first, frames.begin() + last + 1) += target - sum;
            }
        }
        p = last + 1;
    }
}

}
