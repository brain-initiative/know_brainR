# Voxel level NIR propagation simulator (second prototype)

#' Given an environment, e, containing
#'  1. an initialized state array for a voxelized volume of interest,
#'  2. three accessor functions, pAbsorption(id), pBoundary(id), and pFlow(id1, id2),
#'  3. an array of functions, between_steps, to execute in sequence between simulation, steps
#'  4. a variable, step, initialized to 0,
#' execute nsteps of simulation (i.e., approximately nsteps/500 nanoseconds.)
voxSim <- function(e, nsteps){
  stat_arrays <- c("absorbed", "xplus", "xminus", "yplus", "yminus", "zplus", "zminus") 
  initialized <- all(sapply(stat_arrays, function(x)exists(x, e, inherits=FALSE)))
  if(!initialized)initSimStatArrays(e)
  nx = dim(e$state)[2]
  ny = dim(e$state)[3]
  nz = dim(e$state)[4]
  for(istep in 1:nsteps){
    # Custom functions to be executed between steps
    for(fct in e$between_steps)fct(e)
    # Step:
    energy <- e$state[2,,,]
    # Absorption
    a <- energy*e$absorbed
    e$state[3,,,] <- e$state[3,,,] + a
    e$state[2,,,] <- e$state[2,,,] - a
    # Flow
    #  in +x direction
    outflow <- energy*e$xplus
    e$state[2,,,] <- e$state[2,,,] - outflow
    e$state[2,-1,,] <- e$state[2,-1,,] + outflow[-nx,,]
    #  in -x direction
    outflow <- energy*e$xminus
    e$state[2,,,] <- e$state[2,,,] - outflow
    e$state[2,-nx,,] <- e$state[2,-nx,,] + outflow[-1,,]
    #  in +y direction
    outflow <- energy*e$yplus
    e$state[2,,,] <- e$state[2,,,] - outflow
    e$state[2,,-1,] <- e$state[2,,-1,] + outflow[,-ny,]
    #  in -y direction
    outflow <- energy*e$yminus
    e$state[2,,,] <- e$state[2,,,] - outflow
    e$state[2,,-ny,] <- e$state[2,,-ny,] + outflow[,-1,]
    #  in +z direction
    outflow <- energy*e$zplus
    e$state[2,,,] <- e$state[2,,,] - outflow
    e$state[2,,,-1] <- e$state[2,,,-1] + outflow[,,-nz]
    #  in -z direction
    outflow <- energy*e$zminus
    e$state[2,,,] <- e$state[2,,,] - outflow
    e$state[2,,,-nz] <- e$state[2,,,-nz] + outflow[,,-1]
    e$step <- e$step + 1
  }
  e
}

#' Initialize arrays of absorption and flow statistics for componentwise
#' application to the voxelized volume contained in the environment, e.
#' Componentwise arithmetic is done by compiled libraries in R, hence
#' has performance advantages over interpreted loops.
initSimStatArrays <- function(e){
  nx = dim(e$state)[2]
  ny = dim(e$state)[3]
  nz = dim(e$state)[4]
  # Fraction of voxel energies absorbed per step
  e$absorbed <- array(sapply(as.vector(e$state[1,,,]), e$pAbsorption),
                      c(nx,ny,nz))
  # Fraction of voxel photons encountering each of 6 voxel boundaries
  bdry <- array(sapply(as.vector(e$state[1,,,]), function(i)e$pBoundary(i))/6,
                c(nx,ny,nz))
  # Boundaries in the +x and -x directions
  v1 <- as.vector(e$state[1,-nx,,])
  v2 <- as.vector(e$state[1,-1,,])
  e$xplus <- e$xminus <- bdry
  e$xplus[-nx,,] <- e$xplus[-nx,,]*array(mapply(e$pFlow, v1, v2), c(nx-1,ny,nz))
  e$xminus[-1,,] <- e$xminus[-1,,]*array(mapply(e$pFlow, v2, v1), c(nx-1,ny,nz))
  v1 <- as.vector(e$state[1,,-ny,])
  v2 <- as.vector(e$state[1,,-1,])
  # Boundaries in the +y and -y directions
  e$yplus <- e$yminus <- bdry
  e$yplus[,-ny,] <- e$yplus[,-ny,]*array(mapply(e$pFlow, v1, v2), c(nx,ny-1,nz))
  e$yminus[,-1,] <- e$yminus[,-1,]*array(mapply(e$pFlow, v2, v1), c(nx,ny-1,nz))
  # Boundaries in the +z and -z directions
  v1 <- as.vector(e$state[1,,,-nz])
  v2 <- as.vector(e$state[1,,,-1])
  e$zplus <- e$zminus <- bdry
  e$zplus[,,-nz] <- e$zplus[,,-nz]*array(mapply(e$pFlow, v1, v2), c(nx,ny,nz-1))
  e$zminus[,,-1] <- e$zminus[,,-1]*array(mapply(e$pFlow, v2, v1), c(nx,ny,nz-1))
  TRUE
}

#' Test random entries of e$absorbed for correctness. 
testAbsorption <- function(e, ntests, seed){
  set.seed(seed)
  nx = dim(e$state)[2]
  ny = dim(e$state)[3]
  nz = dim(e$state)[4]
  for(k in 1:ntests){
    ix <- sample(nx, 1)
    iy <- sample(ny, 1)
    iz <- sample(nz, 1)
    if(!isTRUE(all.equal(e$absorbed[ix,iy,iz], e$pAbsorption(e$state[1,ix,iy,iz])))){
      stop(paste("Absorption problem", ix, iy, iz))
    }
  }
  return(TRUE)
}

#' Test random entries of e's flow arrays for correctness.
testFlow <- function(e, ntests, seed){
  set.seed(seed)
  nx = dim(e$state)[2]
  ny = dim(e$state)[3]
  nz = dim(e$state)[4]
  for(k in 1:ntests){
    ix <- sample(nx-1, 1)
    iy <- sample(ny-1, 1)
    iz <- sample(nz-1, 1)
    id1 <- e$state[1,ix,iy,iz]
    id2 <- e$state[1,ix+1, iy, iz]
    id3 <- e$state[1,ix, iy+1, iz]
    id4 <- e$state[1,ix, iy, iz+1]
    if(!isTRUE(all.equal(e$xplus[ix,iy,iz], e$pFlow(id1,id2)*e$pBoundary(id1)/6))){
      stop(paste("xplus problem", ix, iy, iz))
    }
    if(!isTRUE(all.equal(e$xminus[ix+1,iy,iz], e$pFlow(id2, id1)*e$pBoundary(id2)/6))){
      stop(paste("xminus problem",  ix+1, iy, iz))
    }
    if(!isTRUE(all.equal(e$yplus[ix,iy,iz], e$pFlow(id1,id3)*e$pBoundary(id1)/6))){
      stop(paste("yplus problem",  ix, iy, iz))
    }
    if(!isTRUE(all.equal(e$yminus[ix,iy+1,iz], e$pFlow(id3,id1)*e$pBoundary(id3)/6))){
      stop(paste("yminus problem",  ix, iy+1, iz))
    }
    if(!isTRUE(all.equal(e$zplus[ix,iy,iz], e$pFlow(id1,id4)*e$pBoundary(id1)/6))){
      stop(paste("zplus problem", ix, iy, iz))
    }
    if(!isTRUE(all.equal(e$zminus[ix,iy,iz+1], e$pFlow(id4,id1)*e$pBoundary(id4)/6))){
      stop(paste("zminus problem",  ix, iy, iz+1))
    }
  }
  return(TRUE)
}
