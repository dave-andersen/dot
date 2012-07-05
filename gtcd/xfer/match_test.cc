#include "async.h"
#include "ihash.h"
#include "bench.h"
#include "rxx.h"

struct lcs_entry {
    str id;
    double dist;
    ihash_entry<lcs_entry> hlink;

    lcs_entry (str id);
    ~lcs_entry ();
};

static ihash<const str, lcs_entry, &lcs_entry::id, &lcs_entry::hlink> lcsCache;

lcs_entry::lcs_entry(str i)
    : id(i)
{
    lcsCache.insert(this);
}

lcs_entry::~lcs_entry()
{
    lcsCache.remove(this);
}

double
dir_match(char *str1, char *str2)
{
#if CACHE
    str key = strbuf() << str1 << ":" << str2;
    lcs_entry *lcs = lcsCache[key];
    if (lcs) {
	return(lcs->dist);
    }
    else {
	str key1 = strbuf() << str2 << ":" << str1;
	lcs = lcsCache[key1];
	if (lcs) {
	    return(lcs->dist);
	}
    }
    //bindu
    //return(0.5);
#endif
    
    vec<char *> *p1 = New vec<char *>;
    vec<char *> *p2 = New vec<char *>;

    //char *cp = strdup(str1);
    //char *tp = strdup(str2);

    char *cp = str1;
    char *tp = str2;

    if (*cp == '/')
	p1->push_back("/");
    if (*tp == '/')
	p2->push_back("/");

    char *line, *brkt;
    for (line = strtok_r(cp, "/", &brkt);  
         line; line = strtok_r(NULL, "/", &brkt)) {
        //str a(line, strlen(line));
	//p1->push_back(a);
        p1->push_back(line);
    }

    for (line = strtok_r(tp, "/", &brkt);  
         line; line = strtok_r(NULL, "/", &brkt)) {
        //str a(line, strlen(line));
	//p2->push_back(a);
        p2->push_back(line);
    }

    double dist = 0;
    int s1 = p1->size();
    int s2 = p2->size();
    int max_len = max(s1, s2);
    vec<char *> *sm;
    vec<char *> *lg;
    if (s1 > s2) {
	sm = p2; lg = p1;
    }
    else {
	sm = p1; lg = p2;
    }

    //leftmost match
    //warnx << "LEFTMOST\n------------------------------------\n";
    unsigned int lmatch = 0;
    double ldist = 0;
    for (unsigned int i = 0; i < sm->size(); i++) {
	if (strcmp((*sm)[i], (*lg)[i]) != 0)
	    break;
	else {
	    //warnx << (*sm)[i] << " ";
	    lmatch++;
	}
    }
    //warnx << "\n";
    ldist = ((double)lmatch)/max_len;
    dist = ldist*ldist;
    //fprintf(stderr, "left is %f\n", dist);
    //warnx << "-----------------------------------\n";
    
    //rightmost match
    //warnx << "RIGHTMOST\n-------------------------------------\n";
    unsigned int rmatch = 0;
    double rdist = 0;
    unsigned int j = lg->size()-1;
    for (int i = sm->size()-1; i >= 0; i--) {
	if (strcmp((*sm)[i], (*lg)[j]) != 0)
	    break;
	else {
	    //warnx << (*sm)[i] << " " ;
	    rmatch++;
	    j--;
	}
    }
    rdist = ((double)rmatch)/max_len;

    if (rdist > dist)
	dist = rdist;
    //fprintf(stderr, "right is %f and dist %f\n", rdist, dist);
    //warnx << "-----------------------------------\n";

    if (0) {
    //middle match
    //warnx << "MIDDLEMOST\n-----------------------------------\n";
    unsigned int mmatch = 0;
    double mdist = 0;
    {
	int *L = new int[(s1+1)*(s2+1)];
	bzero(L, sizeof(int)*(s1+1)*(s2+1));
	int z = 0;
	str ret = "";
	int len = -1;
	
	for (int i = 0; i < s1; i++) {
	    for (int j = 0; j < s2; j++) {
		if ((*p1)[i] == (*p2)[j]) {
		    
		    L[(i+1)*(s2+1)+j+1] = L[i*(s2+1)+j] + 1;
		    
		    if (L[(i+1)*(s2+1)+j+1] >= z) {
			z = L[(i+1)*(s2+1)+j+1];
			ret = "";
		    }
		    if (L[(i+1)*(s2+1)+j+1] == z) {
			len = z;
			//warnx << i << "|" << i-z+1 << "|" << len << "\n";
			for (int k = i-z+1; k < i-z+1+len; k++) {
			    ret = strbuf() << ret << (*p1)[k];
			}
		    }
		}
	    }
	}
	
	//warnx << "LCS --> " << ret << "\n";
	
	delete[] L;
	mmatch = z;
    }
    
    mdist = ((double)mmatch)/max_len;
    mdist = mdist*mdist;
    
    if (mdist > dist)
	dist = mdist;
    //    fprintf(stderr, "middle is %f and dist %f\n", mdist, dist);
    //warnx << "-----------------------------------\n";
    }
    
#if CACHE
    lcs = New lcs_entry(key);
    lcs->dist = dist;
#endif

    return(dist);
}

#undef U64F
#define U64F "ll"

int
main(int argc, char **argv)
{
    if (argc != 3)
        fatal("%s: need exactly 2 arguments\n", argv[0]);

    double ret;

    BENCH(1000000, ret = dir_match(argv[1], argv[2]);)
    //ret = dir_match(argv[1], argv[2]);

    printf("dir_match returned: %f\n", ret);

    return 0;
}
