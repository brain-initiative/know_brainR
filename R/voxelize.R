#computes probability of reflection
#given angle of incidence (in radians)
#and two indices of refraction, 
#source and dest media respectively
prob_refl <- function(theta1,n1,n2){
  prob <- rep(1,length(theta1))
  cos2 <- rep(0,length(theta1))
  sin1 <- sin(theta1)
  cos1 <- sqrt(1-sin1*sin1)
  sin2 <- (n1/n2) * sin1
  idx <- sin2<=1
  cos2[idx] <- sqrt(1-sin2[idx]^2)
  t1 <-  (abs((n1[idx]*cos1[idx]-n2[idx]*cos2[idx])/(n1[idx]*cos1[idx]+n2[idx]*cos2[idx])))^2
  t2 <-  (abs((n1[idx]*cos2[idx]-n2[idx]*cos1[idx])/(n1[idx]*cos2[idx]+n2[idx]*cos1[idx])))^2  
  prob[idx] <- pmin(1, .5 * (t1+t2))
  prob
}

#compute angles of refraction  in tissue 2 or reflection
#given incidence angles coming from tissue 1
new_angles <- function(theta,n1,n2){
  angles <- numeric(length(theta))
  reflprobs <- prob_refl(theta,n1,n2)
  idx_refl <- reflprobs==1.0
  sin2 <- n1[!idx_refl]/n2[!idx_refl] * sin(theta[!idx_refl])
  cos2 <- sqrt(1-sin2^2)
  angles[idx_refl] <- theta[idx_refl] 
  angles[!idx_refl] <- acos(cos2)
  list(angle=angles,refl=idx_refl)
}
#given nx3 array of  x,y,z positions
#return nx3 array of voxel (i,j,k) indices
#use ceiling since R is 1-based indexing
get_voxel <- function(P){
#  P[,3] <- P[,3]*.2  #pixels are 1x1x1 instead of 1x1x5
  P <- ceiling(P)  
  P
}
phantomize <- function(x){
  return(as.integer(phantom[x[1],x[2],x[3]]))
}
#this will be used when we consider pixels with dyes
#TODO put in concentration of dyes
is_stained <- function(x){
  return(as.integer(phantom[x[1],x[2],x[3]])>99)
}
#given nx3 array of voxel indices
#return n array of tissue type
get_tissuetype <- function(V){
  n <- nrow(V)
  tissue <- rep(0,n)
  tissue <- apply(V,1,phantomize)
  tissue
}
#given nx3 array of voxel indices
#return n array of boolean indicating
#which voxels are stained
get_stained <- function(V){
  n <- nrow(V)
  stained <- rep(0,n)
  stained <- apply(V,1,is_stained)
  stained
}
# candir is nx3 array of differences in voxel coordinates
#check if only 1 coord differs
check_canonical <- function(candir){
  #if any rows have more than 1 differing coordinate
  #pick one of these at random and zeroize the rest
  more <- rowSums(abs(candir) > 0)
  for (i in 1:nrow(candir)) if (more[i]>1)  candir[i,-sample(which(candir[i,]!=0),1)] <- 0
  candir
}
# run from directory know_braimR
# read_phantom <- function(){
# fname <- "data/subject04_crisp_v.rawb"
# # Read in raw bytes as a vector
# phantom <- readBin(fname, what="raw", n=362*434*362, size=1, signed=FALSE, endian="big")
# # Convert to a 3D array by setting the dim attribute
# dim(phantom) <- c(362, 434, 362)
# phantom
# }
read_tissuetable <- function(){
  means <- read.table("data/tissue_properties.csv", sep=",",comment.char="#")
  means <- as.matrix(means,num_types, num_char, byrow=TRUE)
  means
}
create_phantom <- function(ty1,ty2){
  phantom <- numeric(27)
  dim(phantom) <- c(3,3,3)
  phantom[1:3,1:3,1:3] <- ty2
  phantom[2,2,2] <- ty1
  phantom  
}


# Simulates scattering and absorption in a phantom head
# assuming nphotons are emitted at the skull with g=.94 
get_pairchars <- function(ty1,ty2,phantom,nphotons=10000, myseed=0x1234567){

  set.seed(myseed)
  
  ty1 <- as.integer(ty1)
  ty2 <- as.integer(ty2)
  

  #state holds position, direction,and condition, i.e., alive, absorbed,exit of each photon
  state = list(P = cbind(x=runif(nphotons,1,2), y=runif(nphotons,1,2), z=runif(nphotons,1,2)),
               D = rusphere(nphotons),
               flg = rep("Alive",nphotons))
 
  mu_s <- numeric(nphotons)
  mu_a <- numeric(nphotons)
  g <- numeric(nphotons)
  n1 <- numeric(nphotons)
  src_angles <- numeric()
  new_ang <- list()
  
  #get scattering and absorption coeff and index of refraction for source tissues
  #add 1 to tissue1 because tissues are labeled 0..n and lists are indexed 1..n+1
  V <- get_voxel(state$P)
  tissue1 <- get_tissuetype(V)
  mu_s <- tissue_char$mu_s[1+tissue1]
  mu_a <- tissue_char$mu_a[1+tissue1]
  n1 <- tissue_char$n[1+tissue1]
  g <- tissue_char$g[1+tissue1]
  invCDF <- lapply(g,icdfHG)

  # step provisionally, ignoring voxel boundaries
  provisional_step <- move_provisionally(state$P, state$D, mu_s, mu_a)
  
  #see what boundaries the provisional steps of photons have crossed
  xing <- find_intersects(state$P,provisional_step$P)
  
  #change destination points if there were crossings to diff tissues
  newP <- process(xing,state$P,provisional_step$P,tissue1)
  VP <- get_voxel(newP$P)
  tissue2 <- get_tissuetype(VP)
  n2 <- numeric(length(newP$idim))
  n2 <- tissue_char$n[1+tissue2]

 
  #check if destination tissue is different from source tissue
  diff_tiss <- tissue1 != tissue2
  #first get canonical direction of movement (left/right, above/below, front/behind)
  candir <- VP[diff_tiss,]-V[diff_tiss,]
  if (sum(diff_tiss)==1){
    dim(candir) <- c(1,3)
  }
  if ((nrow(candir)>0)){
    #check candir  to see if there's more than one canonical direction in any row
    candir <- check_canonical(candir)
    src_angles[diff_tiss] <- acos(rowSums(candir*state$D[diff_tiss,]))
    #compute new angles of reflection and refraction
    temp <- new_angles(src_angles[diff_tiss],n1[diff_tiss],n2[diff_tiss])
    
    #compute directions for all photons(reflected and refracted)
    #which hit different tissue types
    state$D[diff_tiss,] <- compute_direction(temp,candir,newP$idim[diff_tiss],state$D[diff_tiss,1:3])
    new_ang <- list(angle=numeric(nphotons),refl=logical(nphotons))
    new_ang$angle[diff_tiss]<-temp$angle
    new_ang$refl[diff_tiss] <- temp$refl
    
  }
  else{
    new_ang <- list(angle=numeric(nphotons),refl=logical(nphotons))
  }
  new_ang$refl[!diff_tiss] <- FALSE
  
  #if reflected (hence different  tissues), put photon back in direction of source voxel
  #note that dimension that's being changed is an integer, i.e., voxel boundary
  #   if  ((nrow(candir)>0)&(sum(new_ang$refl)>0))
  #   {
  #     print(n)
  #   }
  for (i in 1:nphotons) if (new_ang$refl[i]) newP$P[i,newP$idim[i]] <- newP$P[i,newP$idim[i]]-newP$ndir[i]
  state$P <- newP$P
  
  #check to see if any photons have hit background voxels and aren't reflected back
  exits <- mark_exits(state$P,new_ang$refl)
  state$flg[exits] <- "Exited"
  # extract exit positions
  X <- matrify(state$P, exits)
  # extract absorbed positions with are not exits and not different tissues
  absorbed <- provisional_step$absorptions & !diff_tiss & !exits
  state$flg[absorbed] <- "Absorbed"
  A <- matrify(state$P, absorbed)
  #mark photons that haven't exited or been absorbed
  alive <- !(exits | absorbed)
  state$flg[alive] <- "Alive"
  V <- get_voxel(state$P)
  Vf <- rowSums(V[,1:3]!=2)>0
  # scatter the remaining photons
  #for (i in 1:nphotons) if (state$flg[i]=="Alive") state$D[i,1:3] <-scatter1(state$D[i,1:3],invCDF[[i]](runif(1))) 
#   print(paste("Number leaving source is ",sum(Vf)))
#   print(paste("Number absorbed is ",sum(absorbed)))
  # return P, D, X, A, and indicator flag
  list(P=state$P, D=state$D, V=Vf, X=X, A=A, absorbed=absorbed,flg=state$flg,seed=myseed,tchar=tissue_char)

}
num_types <-12
num_char <- 6
get_tissue_chars <- function(){
  means <- read_tissuetable()
  std_dev <- matrix(0.000001,nrow=num_types,ncol=num_char)
  std_dev[c(9,11,12),5] <- .01
  tissue_char <- as.data.frame(gen_tissue_chars(means,std_dev) )
  names(tissue_char) <- c("id",  "mu_a","mu_s","g","n","W") 
  tissue_char
}#end of get_tissue_chars
gen_tissue_chars <- function(means,std_dev){
  temp <- matrix(0,num_types,num_char)
  for (i in 1:num_types){
    temp[i,1] <- means[i,1]
    for (j in 2:num_char) temp[i,j] <- rnorm(1,means[i,j],std_dev[i,j])
  }
  temp
}

tissue_char <- get_tissue_chars()

#z bottom to top
#y back to front
#x left to right
#given 2 nx3 arrays of source and dest points
find_intersects <- function(P1,P2){
  n <- nrow(P1)
  stor <- lapply(1:n,function(x){findVoxelCrossings(P1[x,],P2[x,])})
  stor
}

#Given n-long list of crossing points, 
#n source and n provisional destination points,
#and origin tissue type
#see if crossings go into different tissues
process <- function(xing,src,dest,tissue1){
  n <- nrow(src)
  temp <- matrix(0,n,3)
  idim <- numeric(n)
  ndir <- numeric(n)
  for (i in 1:n)
    if (!is.null(xing[[i]])){
      #compute midpoints between crossings to find voxels correctly
      midpt <- matrix(0,1,3)
      midpt[1,1:3] <- (src[i,1:3] + xing[[i]][1,1:3])/2
      if (nrow(xing[[i]])>1){
        for (j in 2:nrow(xing[[i]])) rbind(midpt, (xing[[i]][j-1,1:3]+xing[[i]][j,1:3])/2)
        midpt <- rbind(midpt, (xing[[i]][nrow(xing[[i]]),1:3]+dest[i,1:3])/2)
      } else  midpt <- rbind(midpt, (xing[[i]][1,1:3]+dest[i,1:3])/2)
      #Pi crossed into different voxels, so see what tissues they are
      tissue2<- get_tissuetype(get_voxel(midpt))
      if (sum(tissue1[[i]]!=tissue2) >0){
        #photon i hits at least 1 different tissue
        #find first voxel crossing with diff tissue
        idx <- which(tissue1[[i]]!=tissue2)[1]
        temp[i,1:3] <- xing[[i]][idx-1,1:3]
        idim[i] <- xing[[i]][idx-1,4]
        if (temp[i,idim[i]] > src[i,idim[i]]) {
          #aim to greater photon in correct dim
          temp[i,idim[i]] <- temp[i,idim[i]]+1
          ndir[i] <- 1
        }
        else ndir[i] <- -1 #aim back
      } else {#all voxels of same tissue type
        temp[i,1:3] <- dest[i,1:3]
        idim[i] <- 0
        ndir[i]<- 0
      }
    }    else {#no crsossing into diff voxels
      temp[i,1:3] <- dest[i,1:3]
      idim[i] <- 0
      ndir[i]<- 0
    }
  list(P=temp,idim=idim,ndir=ndir)
}

#given list of new angles (and associated boolean indicator of reflection),
#canonical directions and dimensions and source directions compute new directions
#new angles are either reflection or refractions indicated by new_angles$refl
compute_direction <- function(new_angles,candir,wdim,D){
  #check to make sure D is matrix
  if (length(D)==3){
    dim(D) <- c(1,3)
  }
  #form vector of +/- 1's from candir and dimension selector wdim
  vdir <- sapply(1:nrow(candir),function(n){candir[n,wdim[n]]})

  #multiply angle by +1 or -1 to indicate direction and compute cosines
  newdir <- cos(new_angles$angle*vdir)
  beta <- sqrt(1-newdir^2)
  #create Boolean of refracted angles
  refraction <- !new_angles$refl  
  #0 out canonical directions in D for refracted angles
  for(i in 1:nrow(D)) if (refraction[i]) D[i,wdim[i]] <- 0
  #compute normalizing factor sqrt of sums of sqrs of noncanonical directions
  denom <- sqrt(rowSums(D^2))[refraction]
  D[refraction,] <- D[refraction,]*beta[refraction]/denom
  #insert canonical direction
  for (i in 1:nrow(D)) if (refraction[i]) D[i,wdim[i]] <- newdir[i]
  #for reflected angles negate sign of canonical direction
  for (i in 1:nrow(D)) if (!refraction[i]) D[i,wdim[i]] <- -D[i,wdim[i]]
  D
}

# R subsetting casts a 1xm matrix to an m-long vector because, after
# all, consistency is the hobgoblin of small minds. This small-minded
# function subsets consistently, using the logical vector idx to
# return a sub-MATRIX of select rows of M.
matrify <- function(M, idx, ncol=3){
  ans <- matrix(M[idx,], ncol=ncol)
  colnames(ans) <- colnames(M)
  try(rownames(ans) <- rownames(M)[idx], silent=FALSE)
  ans
}
# Given a scattering coefficient (not a reduced scattering coefficient,) mu_s,
# and an absorption coefficient, mu_a, both in units of events per mm, and
# given nx3 arrays, P and D, representing positions and directions of travel
# respectively, compute new positions based on randomly sampled
# distances to new events, assuming these occur within the medium of interest.
# Return the new positions along with a logical vector indicating which events
# were absorptions.
# NOTE: The rows of D must be unit vectors.
move_provisionally <- function(P, D, mu_s, mu_a){
  n <- nrow(P)
  scattering_distances <- rexp(n, mu_s)
  absorption_distances <- rexp(n, mu_a)
  absorptions <- scattering_distances > absorption_distances
  P <- P + pmin(scattering_distances, absorption_distances)*D

  list(P=P, absorptions=absorptions)
}
# Given nx3 matrices of positions, P, and directions of motion, D,
# toward those positions, create a logical vectors marking rows
# for which P is in a background voxel
# Return  exit indicators.
mark_exits <- function(P,refl){
  V <- get_voxel(P)
  tissue <- get_tissuetype(V)
  exits <- (tissue==0)&(!refl)
  exits
}


# ty1 <- readline("Enter first tissue type (integer>0) ")
# ty2 <- readline("Enter secnd tissue type (integer>0) ")
phantom <- create_phantom(ty1,ty2)
# get_pairchars(ty1,ty2,phantom,5,0x47616)

