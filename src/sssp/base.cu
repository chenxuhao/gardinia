// Copyright 2016, National University of Defense Technology
// Authors: Xuhao Chen <cxh@illinois.edu>
#define SSSP_VARIANT "base"
#include "sssp.h"
#include "timer.h"
#include "worklistc.h"
#include "cuda_launch_config.hpp"
#include "cutil_subset.h"
/*
Naive CUDA implementation of the Bellman-Ford algorithm for SSSP

[1] A. Davidson, S. Baxter, M. Garland, and J. D. Owens, “Work-efficient
	parallel gpu methods for single-source shortest paths,” in Proceedings
	of the IEEE 28th International Parallel and Distributed Processing
	Symposium (IPDPS), pp. 349–359, May 2014
*/
__global__ void initialize(int m, DistT *dist) {
	unsigned id = blockIdx.x * blockDim.x + threadIdx.x;
	if (id < m) {
		dist[id] = MYINFINITY;
	}
}

/**
 * @brief naive Bellman_Ford SSSP kernel entry point.
 *
 * @param[in] m                 Number of vertices
 * @param[in] d_row_offsets     Device pointer of VertexId to the row offsets queue
 * @param[in] d_column_indices  Device pointer of VertexId to the column indices queue
 * @param[in] d_weight          Device pointer of DistT to the edge weight queue
 * @param[out]d_dist            Device pointer of DistT to the distance queue
 * @param[in] d_in_queue        Device pointer of VertexId to the incoming frontier queue
 * @param[out]d_out_queue       Device pointer of VertexId to the outgoing frontier queue
 */
__global__ void bellman_ford(int m, int *row_offsets, int *column_indices, DistT *weight, DistT *dist, Worklist2 inwl, Worklist2 outwl) {
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	int src;
	if(inwl.pop_id(tid, src)) {
		int row_begin = row_offsets[src];
		int row_end = row_offsets[src + 1];
		for (int offset = row_begin; offset < row_end; ++ offset) {
			int dst = column_indices[offset];
			DistT wt = weight[offset];
			DistT altdist = dist[src] + wt;
			if (altdist < dist[dst]) {
				DistT olddist = atomicMin(&dist[dst], altdist);
				if (altdist < olddist) { // update successfully
					assert(outwl.push(dst));
				}
			}
		}
	}
}

__global__ void insert(int source, Worklist2 inwl) {
	unsigned id = blockIdx.x * blockDim.x + threadIdx.x;
	if(id == 0) {
		inwl.push(source);
	}
	return;
}

/**
 * @brief naive data-driven mapping GPU SSSP entry point.
 *
 * @param[in] m                 Number of vertices
 * @param[in] h_row_offsets     Host pointer of VertexId to the row offsets queue
 * @param[in] h_column_indices  Host pointer of VertexId to the column indices queue
 * @param[in] h_weight          Host pointer of DistT to the edge weight queue
 * @param[out]h_dist            Host pointer of DistT to the distance queue
 */
void SSSPSolver(int m, int nnz, int source, int *h_row_offsets, int *h_column_indices, DistT *h_weight, DistT *h_dist) {
	DistT zero = 0;
	int iteration = 0;
	Timer t;
	int nthreads = 256;
	int nblocks = (m - 1) / nthreads + 1;
	//initialize <<<nblocks, nthreads>>> (m, d_dist);
	//CudaTest("initializing failed");

	int *d_row_offsets, *d_column_indices;
	DistT *d_weight;
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_row_offsets, (m + 1) * sizeof(int)));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_column_indices, nnz * sizeof(int)));
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_weight, nnz * sizeof(DistT)));
	CUDA_SAFE_CALL(cudaMemcpy(d_row_offsets, h_row_offsets, (m + 1) * sizeof(int), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(d_column_indices, h_column_indices, nnz * sizeof(int), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(d_weight, h_weight, nnz * sizeof(DistT), cudaMemcpyHostToDevice));
	DistT * d_dist;
	CUDA_SAFE_CALL(cudaMalloc((void **)&d_dist, m * sizeof(DistT)));
	CUDA_SAFE_CALL(cudaMemcpy(d_dist, h_dist, m * sizeof(DistT), cudaMemcpyHostToDevice));
	CUDA_SAFE_CALL(cudaMemcpy(&d_dist[source], &zero, sizeof(zero), cudaMemcpyHostToDevice));
	Worklist2 wl1(nnz * 2), wl2(nnz * 2);
	Worklist2 *inwl = &wl1, *outwl = &wl2;
	int nitems = 1;
	int max_blocks = maximum_residency(bellman_ford, nthreads, 0);
	printf("Launching CUDA SSSP solver (%d CTAs/SM, %d threads/CTA) ...\n", max_blocks, nthreads);
	t.Start();
	insert<<<1, nthreads>>>(source, *inwl);
	nitems = inwl->nitems();
	do {
		++iteration;
		nblocks = (nitems - 1) / nthreads + 1;
		//printf("iteration=%d, nblocks=%d, nthreads=%d, wlsz=%d\n", iteration, nblocks, nthreads, nitems);
		bellman_ford<<<nblocks, nthreads>>>(m, d_row_offsets, d_column_indices, d_weight, d_dist, *inwl, *outwl);
		CudaTest("solving failed");
		nitems = outwl->nitems();
		Worklist2 *tmp = inwl;
		inwl = outwl;
		outwl = tmp;
		outwl->reset();
	} while (nitems > 0);
	CUDA_SAFE_CALL(cudaDeviceSynchronize());
	t.Stop();
	printf("\titerations = %d.\n", iteration);
	printf("\truntime [%s] = %f ms.\n", SSSP_VARIANT, t.Millisecs());

	CUDA_SAFE_CALL(cudaMemcpy(h_dist, d_dist, m * sizeof(DistT), cudaMemcpyDeviceToHost));
	CUDA_SAFE_CALL(cudaFree(d_row_offsets));
	CUDA_SAFE_CALL(cudaFree(d_column_indices));
	CUDA_SAFE_CALL(cudaFree(d_weight));
	CUDA_SAFE_CALL(cudaFree(d_dist));
	return;
}
