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
  task_min_count               = 1
  task_max_count               = 10
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
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

run "automatic_max_preserves_host_scaling_headroom" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // Small non-GPU instance: mem cap = (4096-1024-256)/128 = 22 -> ceil(10/22)=1;
    // cpu cap = floor((2*1024-128)/200) = 9. Two hosts provide enough task
    // slots, but the automatic maximum remains one host above the ASG minimum.
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
    error_message = "asg_max_size: expected one host of scaling room above the two-host minimum"
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

run "partial_final_host_supplies_rollout_slot" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // Two tasks fit per host. Nineteen steady tasks plus one replacement need
    // twenty slots, so ten hosts are sufficient; an eleventh would be waste.
    instance_memory_mib    = 16384
    instance_vcpus         = 32
    task_max_count         = 19
    container_cpu          = 128
    container_memory       = 5120
    daemon_memory_overhead = 512
  }

  assert {
    condition     = output.asg_max_size == 10
    error_message = "asg_max_size: expected 20 task slots on 10 hosts, got ${output.asg_max_size}"
  }
}

run "small_instance_keeps_single_task_floor" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    instance_memory_mib    = 1024
    instance_vcpus         = 2
    task_min_count         = 1
    task_max_count         = 1
    container_memory       = 128
    daemon_memory_overhead = 256
    subnet_count           = 1
  }

  assert {
    condition     = output.asg_max_size == 2
    error_message = "asg_max_size: expected the t3.micro-sized configuration to remain valid"
  }
}

run "fractional_cpu_capacity_uses_whole_task_slots" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // A host has 3,968 CPU units after daemon reservations. A 1,400-unit task
    // fits twice, not 2.83 times. Five tasks plus one replacement need three hosts.
    instance_vcpus   = 4
    task_max_count   = 5
    container_cpu    = 1400
    container_memory = 128
  }

  assert {
    condition     = output.asg_max_size == 3
    error_message = "asg_max_size: expected six task slots on three hosts, got ${output.asg_max_size}"
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

run "gpu_task_on_non_gpu_host_rejected" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    instance_gpus = 0
    gpu_count     = 1
  }

  expect_failures = [output.asg_max_size]
}

run "consumer_asg_max_size_above_requirement_wins" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    // Ten one-GPU tasks plus one replacement require eleven hosts. A larger
    // explicit cost ceiling remains valid and wins.
    instance_gpus         = 1
    gpu_count             = 1
    task_max_count        = 10
    consumer_asg_max_size = 12
  }

  assert {
    condition     = output.asg_max_size == 12
    error_message = "asg_max_size: expected user override 12, got ${output.asg_max_size}"
  }
}

run "consumer_asg_max_size_below_requirement_rejected" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    instance_memory_mib    = 16384
    instance_vcpus         = 32
    task_max_count         = 20
    container_cpu          = 128
    container_memory       = 5120
    daemon_memory_overhead = 512
    consumer_asg_max_size  = 10
  }

  expect_failures = [output.asg_max_size]
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
    error_message = "asg_max_size: expected one host of scaling room above the four-host minimum"
  }
}

run "stop_first_deployment_needs_only_steady_state_slots" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    instance_memory_mib                = 16384
    instance_vcpus                     = 32
    task_min_count                     = 20
    task_max_count                     = 20
    deployment_minimum_healthy_percent = 95
    deployment_maximum_percent         = 100
    container_cpu                      = 128
    container_memory                   = 5120
    daemon_memory_overhead              = 512
  }

  assert {
    condition     = output.asg_max_size == 10
    error_message = "asg_max_size: expected ten hosts for a stop-first rollout, got ${output.asg_max_size}"
  }
}

run "minimum_healthy_ceil_allows_stop_at_66_percent" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    task_min_count                     = 3
    task_max_count                     = 3
    deployment_minimum_healthy_percent = 66
    deployment_maximum_percent         = 100
    subnet_count                       = 1
    consumer_asg_max_size              = 1
  }

  assert {
    condition     = output.asg_max_size == 1
    error_message = "asg_max_size: expected ceil(3 * 66%) = 2 to permit a stop-first deployment"
  }
}

run "minimum_healthy_ceil_blocks_stop_at_67_percent" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    task_min_count                     = 3
    task_max_count                     = 3
    deployment_minimum_healthy_percent = 67
    deployment_maximum_percent         = 100
  }

  expect_failures = [output.asg_max_size]
}

run "stateful_singleton_stop_first_is_valid" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    task_min_count                     = 1
    task_max_count                     = 1
    deployment_minimum_healthy_percent = 0
    deployment_maximum_percent         = 100
    subnet_count                       = 1
    consumer_asg_max_size              = 1
  }

  assert {
    condition     = output.asg_max_size == 1
    error_message = "asg_max_size: expected one host for a stop-first singleton, got ${output.asg_max_size}"
  }
}

run "deployment_with_no_first_move_rejected" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    task_min_count                     = 1
    task_max_count                     = 20
    deployment_minimum_healthy_percent = 100
    deployment_maximum_percent         = 150
  }

  expect_failures = [output.asg_max_size]
}

run "task_leaving_no_host_memory_rejected" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    instance_memory_mib = 4096
    container_memory    = 3840
  }

  expect_failures = [output.asg_max_size]
}

run "task_too_large_for_host_cpu_rejected" {
  command = plan
  module { source = "./modules/scaling" }

  variables {
    instance_vcpus = 1
    container_cpu  = 1000
  }

  expect_failures = [output.asg_max_size]
}
