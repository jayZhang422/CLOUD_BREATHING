// Experimental instrumented Lee coordinator; not selected by the application.
// Algorithm and tables adapted from scikit-image 0.25.2 _skeletonize_lee_cy.pyx.in.
// See SCIKIT_IMAGE_LICENSE.txt and _lee_reference.pyx.in for attribution/license.
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <vector>

using Clock = std::chrono::steady_clock;
static double seconds(Clock::time_point t) {
    return std::chrono::duration<double>(Clock::now() - t).count();
}

static constexpr int euler_lut[128] = {
    1,-1,-1,1,-3,-1,-1,1,-1,1,1,-1,3,1,1,-1,-3,-1,
    3,1,1,-1,3,1,-1,1,1,-1,3,1,1,-1,-3,3,-1,1,1,
    3,-1,1,-1,1,1,-1,3,1,1,-1,1,3,3,1,5,3,3,1,
    -1,1,1,-1,3,1,1,-1,-7,-1,-1,1,-3,-1,-1,1,-1,
    1,1,-1,3,1,1,-1,-3,-1,3,1,1,-1,3,1,-1,1,1,
    -1,3,1,1,-1,-3,3,-1,1,1,3,-1,1,-1,1,1,-1,3,
    1,1,-1,1,3,3,1,5,3,3,1,-1,1,1,-1,3,1,1,-1
};
static constexpr int euler_octants[8][7] = {
    {2,1,11,10,5,4,14}, {0,9,3,12,1,10,4},
    {8,7,17,16,5,4,14}, {6,15,7,16,3,12,4},
    {20,23,19,22,11,14,10}, {18,21,9,12,19,22,10},
    {26,23,17,14,25,22,16}, {24,25,15,16,21,22,12}
};
// The reference's numbering excludes the center (13) in the octree cube.
static constexpr int octree_points[8][7] = {
    {0,1,3,4,9,10,12}, {1,4,10,2,5,11,13},
    {3,4,12,6,7,14,15}, {4,5,13,7,15,8,16},
    {9,10,12,17,18,20,21}, {10,11,13,18,21,19,22},
    {12,14,15,20,21,23,24}, {13,15,16,21,22,24,25}
};
static constexpr int octree_links[8][7][3] = {
    {{0,0,0},{2,0,0},{3,0,0},{2,3,4},{5,0,0},{2,5,6},{3,5,7}},
    {{1,0,0},{1,3,4},{1,5,6},{0,0,0},{4,0,0},{6,0,0},{4,6,8}},
    {{1,0,0},{1,2,4},{1,5,7},{0,0,0},{4,0,0},{7,0,0},{4,7,8}},
    {{1,2,3},{2,0,0},{2,6,8},{3,0,0},{3,7,8},{0,0,0},{8,0,0}},
    {{1,0,0},{1,2,6},{1,3,7},{0,0,0},{6,0,0},{7,0,0},{6,7,8}},
    {{1,2,5},{2,0,0},{2,4,8},{5,0,0},{5,7,8},{0,0,0},{8,0,0}},
    {{1,3,5},{3,0,0},{3,4,8},{5,0,0},{5,6,8},{0,0,0},{8,0,0}},
    {{2,4,6},{3,4,7},{4,0,0},{5,6,7},{6,0,0},{7,0,0},{0,0,0}}
};
static void label_octant(int octant, int label, uint8_t cube[26]) {
    for (int j = 0; j < 7; ++j) {
        int i = octree_points[octant][j];
        if (cube[i] == 1) {
            cube[i] = label;
            for (int k = 0; k < 3; ++k) {
                int next = octree_links[octant][j][k];
                if (next) label_octant(next - 1, label, cube);
            }
        }
    }
}
static bool simple_reference(uint32_t n) {
    uint8_t cube[26];
    for (int i = 0; i < 26; ++i) cube[i] = (n >> (i < 13 ? i : i+1)) & 1;
    int label = 2;
    for (int i = 0; i < 26; ++i) {
        if (cube[i] == 1) {
            int octant = 0;
            while (octant < 8 && std::find(octree_points[octant],
                   octree_points[octant]+7, i) == octree_points[octant]+7) ++octant;
            label_octant(octant, label, cube);
            if (++label >= 4) return false;
        }
    }
    return true;
}
static const std::array<uint32_t,8> octant_masks = [] {
    std::array<uint32_t,8> result{};
    for (int k = 0; k < 8; ++k)
        for (int j = 0; j < 7; ++j) result[k] |= 1u << euler_octants[k][j];
    return result;
}();
// Equivalent finite connectivity closure for hardware, independently checked
// against the reference's recursive octree on all 2^26 neighborhoods.
static bool simple_bits(uint32_t n) {
    n &= ~(1u << 13);
    uint32_t reached = n & -n;
    for (int step = 0; step < 8; ++step) {
        uint32_t next = reached;
        for (int k = 0; k < 8; ++k)
            if (reached & octant_masks[k]) next |= n & octant_masks[k];
        if (next == reached) break;
        reached = next;
    }
    return reached == n;
}
static bool euler_invariant(uint32_t n) {
    int sum = 0;
    for (int k = 0; k < 8; ++k) {
        int index = 0;
        for (int j = 0; j < 7; ++j)
            index |= ((n >> euler_octants[k][j]) & 1) << (6-j);
        sum += euler_lut[index];
    }
    return sum == 0;
}
static bool candidate(uint32_t n, bool bits) {
    return __builtin_popcount(n) != 2 && euler_invariant(n) &&
           (bits ? simple_bits(n) : simple_reference(n));
}

static PyObject* validate_simple(PyObject*, PyObject* args) {
    unsigned long start = 0, count = 1ul << 26;
    if (!PyArg_ParseTuple(args, "|kk", &start, &count)) return nullptr;
    if (start > (1ul << 26) || count > (1ul << 26) - start) {
        PyErr_SetString(PyExc_ValueError, "Neighborhood range exceeds 2^26"); return nullptr;
    }
    auto t = Clock::now();
    uint32_t mismatch = UINT32_MAX;
    Py_BEGIN_ALLOW_THREADS
    for (uint32_t i = start; i < start + count; ++i) {
        uint32_t n = (i & 0x1fff) | (1u<<13) | ((i & ~0x1fffu) << 1);
        if (simple_reference(n) != simple_bits(n)) { mismatch = i; break; }
    }
    Py_END_ALLOW_THREADS
    return Py_BuildValue("{s:k,s:k,s:d,s:i}", "start", start, "count", count,
                         "seconds", seconds(t), "mismatch", int(mismatch));
}

static PyObject* filter_words(PyObject*, PyObject* args) {
    PyObject* words;
    if (!PyArg_ParseTuple(args, "O", &words)) return nullptr;
    Py_buffer b{};
    if (PyObject_GetBuffer(words, &b, PyBUF_CONTIG_RO) < 0) return nullptr;
    if (b.len % 4) { PyBuffer_Release(&b); PyErr_SetString(PyExc_ValueError,"uint32 words required"); return nullptr; }
    PyObject* result = PyBytes_FromStringAndSize(nullptr, b.len/4);
    if (!result) { PyBuffer_Release(&b); return nullptr; }
    const auto* n = static_cast<const uint32_t*>(b.buf);
    auto* out = reinterpret_cast<uint8_t*>(PyBytes_AS_STRING(result));
    Py_BEGIN_ALLOW_THREADS
    for (Py_ssize_t i = 0; i < b.len/4; ++i) out[i] = candidate(n[i], true);
    Py_END_ALLOW_THREADS
    PyBuffer_Release(&b);
    return result;
}

static PyObject* thin(PyObject*, PyObject* args, PyObject* kwargs) {
    PyObject* image;
    PyObject* provider = Py_None;
    const char* scan = "volume";
    int bits = 0;
    static const char* names[] = {"image", "scan", "bits", "provider", nullptr};
    if (!PyArg_ParseTupleAndKeywords(args, kwargs, "O|spO", const_cast<char**>(names),
                                     &image, &scan, &bits, &provider)) return nullptr;
    bool sparse = !std::strcmp(scan,"foreground");
    if (!sparse && std::strcmp(scan,"volume")) { PyErr_SetString(PyExc_ValueError,"Unknown scan"); return nullptr; }
    if (provider != Py_None && !PyCallable_Check(provider)) { PyErr_SetString(PyExc_TypeError,"provider must be callable"); return nullptr; }
    Py_buffer b{};
    if (PyObject_GetBuffer(image, &b, PyBUF_ND | PyBUF_C_CONTIGUOUS | PyBUF_WRITABLE) < 0) return nullptr;
    if (b.ndim != 3 || b.itemsize != 1 || b.len > UINT32_MAX ||
        b.shape[0]<3 || b.shape[1]<3 || b.shape[2]<3) {
        PyBuffer_Release(&b); PyErr_SetString(PyExc_ValueError,"Padded C uint8 3D image required (<4 GiB)"); return nullptr;
    }
    auto* img = static_cast<uint8_t*>(b.buf);
    uint32_t np=b.shape[0], nr=b.shape[1], nc=b.shape[2], plane=nr*nc;
    std::array<int64_t,27> offsets{};
    for(int p=-1;p<=1;++p) for(int c=-1;c<=1;++c) for(int r=-1;r<=1;++r)
        offsets[(p+1)*9+(c+1)*3+r+1] = int64_t(p)*plane+int64_t(r)*nc+c;
    auto neighborhood = [&](uint32_t index) {
        uint32_t n=0;
        for(int k=0;k<27;++k) n |= uint32_t(img[int64_t(index)+offsets[k]] == 1)<<k;
        return n;
    };
    // Reject invalid padding/binary bytes instead of risking unchecked neighbors.
    for(uint32_t p=0;p<np;++p) for(uint32_t r=0;r<nr;++r) for(uint32_t c=0;c<nc;++c) {
        uint8_t v=img[p*plane+r*nc+c];
        if(v>1 || (v && (p==0||p==np-1||r==0||r==nr-1||c==0||c==nc-1))) {
            PyBuffer_Release(&b); PyErr_SetString(PyExc_ValueError,"Image must be binary with zero padding"); return nullptr;
        }
    }
    const int borders[6] = {4,3,2,1,5,6};
    const int64_t border_offsets[6] = {-1,1,int64_t(nc),-int64_t(nc),int64_t(plane),-int64_t(plane)};
    std::vector<uint32_t> active, positions, candidates, words;
    uint64_t initial_fg=0, gathered=0, candidate_count=0, deleted=0, direction_calls=0;
    double gather_sec=0, filter_sec=0, recheck_sec=0, compact_sec=0;
    auto total_started=Clock::now();
    for(uint32_t p=1;p<np-1;++p) for(uint32_t r=1;r<nr-1;++r) for(uint32_t c=1;c<nc-1;++c) {
        uint32_t i=p*plane+r*nc+c;
        if(img[i]) { ++initial_fg; if(sparse) active.push_back(i); }
    }
    int num_borders=np==3?4:6, unchanged=0, iterations=0;
    PyObject* history=PyList_New(0);
    if(!history) { PyBuffer_Release(&b); return nullptr; }
    bool failed=false;
    while(unchanged<num_borders && !failed) {
        unchanged=0; ++iterations;
        for(int j=0;j<num_borders;++j) {
            ++direction_calls;
            int64_t border=border_offsets[borders[j]-1];
            positions.clear(); words.clear(); candidates.clear();
            auto t=Clock::now();
            Py_BEGIN_ALLOW_THREADS
            auto gather=[&](uint32_t i) {
                if(img[i]!=1 || img[int64_t(i)+border]!=0) return;
                positions.push_back(i); words.push_back(neighborhood(i));
            };
            if(sparse) for(uint32_t i:active) gather(i);
            else for(uint32_t p=1;p<np-1;++p) for(uint32_t r=1;r<nr-1;++r)
                for(uint32_t c=1;c<nc-1;++c) gather(p*plane+r*nc+c);
            Py_END_ALLOW_THREADS
            double gather_elapsed=seconds(t); gather_sec+=gather_elapsed; gathered+=words.size();
            t=Clock::now();
            if(provider==Py_None) {
                Py_BEGIN_ALLOW_THREADS
                for(size_t i=0;i<words.size();++i)
                    if(candidate(words[i],bits)) candidates.push_back(positions[i]);
                Py_END_ALLOW_THREADS
            } else if(!words.empty()) {
                PyObject* view=PyMemoryView_FromMemory(reinterpret_cast<char*>(words.data()), words.size()*4, PyBUF_READ);
                PyObject* flags=view?PyObject_CallOneArg(provider,view):nullptr;
                Py_XDECREF(view);
                Py_buffer f{};
                if(!flags) { failed=true; break; }
                if(PyObject_GetBuffer(flags,&f,PyBUF_CONTIG_RO)<0) { Py_DECREF(flags); failed=true; break; }
                if(size_t(f.len)!=words.size()) {
                    PyErr_SetString(PyExc_ValueError,"Candidate provider output length mismatch"); failed=true;
                } else {
                    const auto* values=static_cast<const uint8_t*>(f.buf);
                    for(size_t i=0;i<words.size();++i) {
                        if(values[i]>1) { PyErr_SetString(PyExc_ValueError,"Nonbinary candidate flag"); failed=true; break; }
                        if(values[i]) candidates.push_back(positions[i]);
                    }
                }
                PyBuffer_Release(&f); Py_DECREF(flags);
                if(failed) break;
            }
            double filter_elapsed=seconds(t); filter_sec+=filter_elapsed; candidate_count+=candidates.size();
            t=Clock::now();
            uint64_t removed=0;
            Py_BEGIN_ALLOW_THREADS
            // Preserve exact C-order of the collected candidates and observe
            // every prior deletion. Only simple-point is rechecked in Lee.
            for(uint32_t i:candidates) {
                uint32_t n=neighborhood(i);
                if(bits?simple_bits(n):simple_reference(n)) { img[i]=0; ++removed; }
            }
            Py_END_ALLOW_THREADS
            double recheck_elapsed=seconds(t); recheck_sec+=recheck_elapsed; deleted+=removed;
            if(!removed) ++unchanged;
            PyObject* row=Py_BuildValue("{s:i,s:i,s:K,s:K,s:K,s:d,s:d,s:d}",
                "iteration",iterations,"border",borders[j],"gathered",uint64_t(words.size()),
                "candidates",uint64_t(candidates.size()),"deleted",removed,
                "gather_seconds",gather_elapsed,"filter_seconds",filter_elapsed,"recheck_seconds",recheck_elapsed);
            if(!row || PyList_Append(history,row)<0) { Py_XDECREF(row); failed=true; break; }
            Py_DECREF(row);
            if(PyErr_CheckSignals()<0) { failed=true; break; }
        }
        auto t=Clock::now();
        if(sparse) {
            Py_BEGIN_ALLOW_THREADS
            active.erase(std::remove_if(active.begin(),active.end(),[&](uint32_t i){return img[i]==0;}),active.end());
            Py_END_ALLOW_THREADS
        }
        compact_sec+=seconds(t);
    }
    PyBuffer_Release(&b);
    if(failed) { Py_DECREF(history); return nullptr; }
    PyObject* result=Py_BuildValue("{s:s,s:i,s:i,s:K,s:K,s:K,s:K,s:K,s:d,s:d,s:d,s:d,s:d,s:O}",
        "scan",scan,"bits",bits,"iterations",iterations,"initial_foreground",initial_fg,
        "direction_calls",direction_calls,"gathered",gathered,"candidates",candidate_count,
        "deleted",deleted,"gather_seconds",gather_sec,"filter_seconds",filter_sec,
        "recheck_seconds",recheck_sec,"compact_seconds",compact_sec,"total_seconds",seconds(total_started),"directions",history);
    Py_DECREF(history);
    return result;
}
static PyMethodDef methods[] = {
    {"thin",reinterpret_cast<PyCFunction>(thin),METH_VARARGS|METH_KEYWORDS,"Instrumented exact Lee experiment; mutates padded image."},
    {"validate_simple",validate_simple,METH_VARARGS,"Exhaustive equivalence against recursive octree."},
    {"filter_words",filter_words,METH_VARARGS,"CPU candidate flags for hardware protocol validation."},
    {nullptr,nullptr,0,nullptr}
};
static PyModuleDef module={PyModuleDef_HEAD_INIT,"_lee_native",nullptr,-1,methods};
PyMODINIT_FUNC PyInit__lee_native() { return PyModule_Create(&module); }
