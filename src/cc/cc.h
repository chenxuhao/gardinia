// Copyright (c) 2016, Xuhao Chen

#define CC_VARIANT "topology"
#include "cuda_launch_config.hpp"
#include "cutil_subset.h"

/*
Gardenia Benchmark Suite
Kernel: Connected Components (CC)
Author: Xuhao Chen

Will return comp array labelling each vertex with a connected component ID
This CC implementation makes use of the Shiloach-Vishkin algorithm
*/

using namespace std;
typedef int CompT;

__global__ void initialize(int m, CompT *comp) {
	unsigned id = blockIdx.x * blockDim.x + threadIdx.x;
	if (id < m) {
		comp[id] = id;
	}
}

__global__ void cc_kernel1(int m, int *row_offsets, int *column_indices, CompT *comp, bool *changed) {
	unsigned tid = blockIdx.x * blockDim.x + threadIdx.x;
	int total_inputs = (m - 1) / (gridDim.x * blockDim.x) + 1;
	for (int src = tid; total_inputs > 0; src += blockDim.x * gridDim.x, total_inputs--) {
		if(src < m) {
			int comp_src = comp[src];
			unsigned row_begin = row_offsets[src];
			unsigned row_end = row_offsets[src + 1]; 
			for (unsigned offset = row_begin; offset < row_end; ++ offset) {
				int dst = column_indices[offset];
				int comp_dst = comp[dst];
				if ((comp_src < comp_dst) && (comp_dst == comp[comp_dst])) {
					*changed = true;
					comp[comp_dst] = comp_src;
				}
			}
		}
	}
}

__global__ void cc_kernel2(int m, int *row_offsets, int *column_indices, CompT *comp) {
	unsigned tid = blockIdx.x * blockDim.x + threadIdx.x;
	int total_inputs = (m - 1) / (gridDim.x * blockDim.x) + 1;
	for (int src = tid; total_inputs > 0; src += blockDim.x * gridDim.x, total_inputs--) {
		if(src < m) {
			while (comp[src] != comp[comp[src]]) {
				comp[src] = comp[comp[src]];
			}
		}
	}
}

void ConnectedComponents(int m, int nnz, int *row_offsets, int *column_indices, CompT *comp) {
	bool h_changed, *d_changed;
	double starttime, endtime, runtime;
	int iter = 0;
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_changed, sizeof(bool)));
	const int nthreads = 256;
	int nblocks = (m - 1) / nthreads + 1;
	const size_t max_blocks = maximum_residency(cc_kernel1, nthreads, 0);
	initialize <<<nblocks, nthreads>>> (m, comp);
	//if(nblocks > nSM*max_blocks) nblocks = nSM*max_blocks;
	printf("Solving, max_blocks=%d, nblocks=%d, nthreads=%d\n", max_blocks, nblocks, nthreads);
	starttime = rtclock();
	do {
		++ iter;
		h_changed = false;
		CUDA_SAFE_CALL(cudaMemcpy(d_changed, &h_changed, sizeof(h_changed), cudaMemcpyHostToDevice));
		printf("iteration=%d\n", iter);
		cc_kernel1<<<nblocks, nthreads>>>(m, row_offsets, column_indices, comp, d_changed);
		CudaTest("solving kernel1 failed");
		cc_kernel2<<<nblocks, nthreads>>>(m, row_offsets, column_indices, comp);
		CudaTest("solving kernel2 failed");
		CUDA_SAFE_CALL(cudaMemcpy(&h_changed, d_changed, sizeof(h_changed), cudaMemcpyDeviceToHost));
	} while (h_changed);
	CUDA_SAFE_CALL(cudaDeviceSynchronize());
	endtime = rtclock();
	printf("\titerations = %d.\n", iter);
	runtime = (1000.0f * (endtime - starttime));
	printf("\truntime [%s] = %f ms.\n", CC_VARIANT, runtime);
	CUDA_SAFE_CALL(cudaFree(d_changed));
}
