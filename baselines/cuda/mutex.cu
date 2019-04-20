#include <iostream>
#include <cstdlib>
#include <cstdio>
#include <cuda_runtime.h>
#include <sys/time.h>

double get_time() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  return tv.tv_sec + 1e-6 * tv.tv_usec;
}

constexpr int m = 2;
constexpr int block_size = 128;

struct Node {
  int lock;
  int sum;

  __device__ void inc() {
    /*
    while (atomicCAS(&lock, 0, 1))
      ;
    sum += 1;
    atomicExch(&lock, 0);
     */

    for (int i = 0; i < 32; i++) {
      if (i == threadIdx.x % 32) {
        while (atomicExch(&lock, 1) == 1)
          ;
        // printf("locked\n");
        atomicExch(&lock, 0);
      }
    }
  }
};

__global__ void inc(Node *nodes) {
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

  int b = i % m;
  nodes[b].inc();

  /*
  int warp_id = threadIdx.x % 32;
  int b = warp_id;
  int done = 0;
  if (true) {
    auto mask = __activemask();
    // printf("mask %d\n", mask);
    while (!__all_sync(mask, done)) {
      for (int k = 0; k < 32; k++) {
        if (k == warp_id && !done) {
          int &lock = nodes[b].lock;
          if (atomicCAS(&lock, 0, 1) == 0) {
            nodes[b].sum += 1;
            done = true;
            atomicExch(&lock, 0);
          }
        }
      }
    }
  } else {
    for (int k = 0; k < 32; k++) {
      if (k == warp_id) {
        int &lock = nodes[b].lock;
        while (atomicCAS(&lock, 0, 1))
          ;
        nodes[b].sum += 1;
        done = true;
        atomicExch(&lock, 0);
      }
    }
  }
  */
}

void mutex() {
  Node *a;

  cudaMallocManaged(&a, m * sizeof(Node));

  for (int i = 0; i < 20; i++) {
    cudaDeviceSynchronize();
    auto t = get_time();
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    cudaEventRecord(start);
    cudaDeviceSynchronize();
    inc<<<1, 4>>>((Node *)a);
    cudaEventRecord(stop);
    cudaEventSynchronize(stop);
    float milliseconds = 0;
    cudaEventElapsedTime(&milliseconds, start, stop);
    std::cout << "device  " << milliseconds << std::endl;
    int sum = 0;
    for (int j = 0; j < m; j++) {
      sum += a[j].sum;
    }
    printf("sum %d\n", sum);
  }
  std::cout << std::endl;
}

__global__ void elect(long long *addr_) {
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
  auto addr = addr_[i];
  auto warpId = threadIdx.x % warpSize;

#define FULLMASK 0xFFFFFFFF

  bool has_following_eqiv = 0;
  for (int i = 1; i < warpSize; i++) {
    auto cond = warpId + i < warpSize;
    // auto mask = __ballot_sync(FULLMASK, cond);
    bool same = (addr == __shfl_down_sync(FULLMASK, addr, i));
    if (cond) {
      has_following_eqiv = has_following_eqiv || same;
    }
  }
  if (!has_following_eqiv) {
    printf("%lld\n", addr);
  }
}

void elect_diff() {
  long long *a;

  cudaMallocManaged(&a, 32 * sizeof(long long));

  for (int i = 0; i < 32; i++) {
    a[i] = i % 5;
  }

  for (int i = 0; i < 20; i++) {
    cudaDeviceSynchronize();
    auto t = get_time();
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    cudaEventRecord(start);
    cudaDeviceSynchronize();
    elect<<<1, 32>>>(a);
    cudaEventRecord(stop);
    cudaEventSynchronize(stop);
    float milliseconds = 0;
    cudaEventElapsedTime(&milliseconds, start, stop);
    std::cout << "device  " << milliseconds << std::endl;
  }
  std::cout << std::endl;
}

int main() {
  elect_diff();
}
