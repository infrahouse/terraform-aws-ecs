// Offline unit tests for the ASG sizing math in ./modules/scaling.
// Provider-free: each run targets the submodule with `command = plan`, so these
// execute in milliseconds with no AWS credentials and no real infrastructure.
//
// Run from the repo root:
//   terraform init -test-directory=tests
//   terraform test -test-directory=tests

variables {
  // g4dn.xlarge-ish defaults shared by all runs; individual runs override.
  instance_memory_mib          = 16384
  instance_vcpus               = 4
  instance_gpus                = 0
  task_max_count               = 10
  container_cpu                = 200
  container_memory             = 128
  container_memory_reservation = null
  gpu_count                    = 0
  daemon_cpu_overhead          = 128
  daemon_memory_overhead       = 256
  subnet_count                 = 2
  consumer_asg_min_size        = null
  consumer_asg_max_size        = null
}

run "non_gpu_defaults_unchanged" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // Small non-GPU instance: mem cap = (4096-1024-256)/128 = 22 -> ceil(10/22)=1;
    // cpu cap = (2*1024-128)/200 = 9.6 -> ceil(10/9.6)=2; asg_min = subnet_count = 2,
    // so min+1 = 3 dominates. This matches the pre-refactor behavior.
    instance_memory_mib = 4096
    instance_vcpus      = 2
    instance_gpus       = 0
    gpu_count           = 0
  }

  assert {
    condition     = output.asg_min_size == 2
    error_message = "asg_min_size: expected subnet_count=2, got ${output.asg_min_size}"
  }
  assert {
    condition     = output.asg_max_size == 3
    error_message = "asg_max_size: expected max(1,2,3)=3, got ${output.asg_max_size}"
  }
}

run "fractional_memory_capacity_uses_whole_task_slots" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // A host has 14,848 MiB available after OS and daemon reservations.
    // A 5,120 MiB task therefore fits twice, not 2.9 times. Twenty tasks need
    // ten hosts plus one spare host for rolling deployments.
    instance_memory_mib    = 16384
    instance_vcpus         = 32
    task_max_count         = 20
    container_cpu          = 128
    container_memory       = 5120
    daemon_memory_overhead = 512
  }

  assert {
    condition     = output.asg_max_size == 11
    error_message = "asg_max_size: expected 10 workload hosts plus 1 spare, got ${output.asg_max_size}"
  }
}

run "fractional_cpu_capacity_uses_whole_task_slots" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // A host has 3,968 CPU units after daemon reservations. A 1,400-unit task
    // fits twice, not 2.83 times. Six tasks need three hosts plus one spare.
    instance_vcpus   = 4
    task_max_count   = 6
    container_cpu    = 1400
    container_memory = 128
  }

  assert {
    condition     = output.asg_max_size == 4
    error_message = "asg_max_size: expected 3 workload hosts plus 1 spare, got ${output.asg_max_size}"
  }
}

run "gpu_single_gpu_per_host_dominates" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // g4dn.xlarge: 1 GPU. Ten tasks need ten hosts plus one spare.
    // CPU/memory terms are ~1, so the GPU term dominates. Before this fix the
    // sizing ignored GPUs and would have returned ~3.
    instance_gpus  = 1
    gpu_count      = 1
    task_max_count = 10
  }

  assert {
    condition     = output.asg_max_size == 11
    error_message = "asg_max_size: expected GPU-bound 10 plus 1 spare, got ${output.asg_max_size}"
  }
}

run "gpu_multi_gpu_per_host" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // g4dn.12xlarge: 4 GPUs. Twenty tasks need five hosts plus one spare.
    instance_gpus  = 4
    gpu_count      = 1
    task_max_count = 20
  }

  assert {
    condition     = output.asg_max_size == 6
    error_message = "asg_max_size: expected GPU-bound 5 plus 1 spare, got ${output.asg_max_size}"
  }
}

run "gpu_count_two_on_four_gpu_host" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // 4 GPUs, gpu_count=2. Ten tasks need five hosts plus one spare.
    instance_gpus  = 4
    gpu_count      = 2
    task_max_count = 10
  }

  assert {
    condition     = output.asg_max_size == 6
    error_message = "asg_max_size: expected GPU-bound 5 plus 1 spare, got ${output.asg_max_size}"
  }
}

run "gpu_count_exceeds_host_gpus_rejected" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // A task needing 2 GPUs cannot fit on a 1-GPU instance. The submodule's
    // output precondition must reject this rather than silently mis-size.
    instance_gpus = 1
    gpu_count     = 2
  }

  expect_failures = [output.asg_max_size]
}

run "consumer_asg_max_size_wins" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // Even with a GPU-bound calculation that would yield 100, an explicit
    // consumer override takes precedence.
    instance_gpus         = 1
    gpu_count             = 1
    task_max_count        = 100
    consumer_asg_max_size = 7
  }

  assert {
    condition     = output.asg_max_size == 7
    error_message = "asg_max_size: expected user override 7, got ${output.asg_max_size}"
  }
}

run "consumer_asg_min_size_wins" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    consumer_asg_min_size = 4
  }

  assert {
    condition     = output.asg_min_size == 4
    error_message = "asg_min_size: expected user override 4, got ${output.asg_min_size}"
  }
  assert {
    condition     = output.asg_max_size == 5
    error_message = "asg_max_size: expected min+1=5, got ${output.asg_max_size}"
  }
}
