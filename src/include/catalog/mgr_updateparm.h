
#ifndef MGR_UPDATEPARM_H
#define MGR_UPDATEPARM_H

#ifdef BUILD_BKI
#include "catalog/buildbki.h"
#else /* BUILD_BKI */
#include "catalog/genbki.h"
#endif /* BUILD_BKI */


#define UpdateparmRelationId 3846

CATALOG(mgr_updateparm,3846) BKI_WITHOUT_OIDS
{
	char		updateparmparmtype;			/* updateparm type:c/d/g*/
	NameData	updateparmnodename;			/* updateparm nodename */
	char		updateparmnodetype;
	NameData	updateparmkey;
	NameData	updateparmvalue;
	/* CATALOG_VARLEN */
} FormData_mgr_updateparm;

/* ----------------
 *		Form_mgr_updateparm corresponds to a pointer to a tuple with
 *		the format of mgr_updateparm relation.
 * ----------------
 */
typedef FormData_mgr_updateparm *Form_mgr_updateparm;

/* ----------------
 *		compiler constants for mgr_updateparm
 * ----------------
 */
#define Natts_mgr_updateparm				5
#define Anum_mgr_updateparm_parmtype		1
#define Anum_mgr_updateparm_nodename		2
#define Anum_mgr_updateparm_nodetype		3
#define Anum_mgr_updateparm_key				4
#define Anum_mgr_updateparm_value			5

#define MACRO_STAND_FOR_ALL_NODENAME "*"

#endif /* MGR_UPDATEPARM_H */
