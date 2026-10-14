using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using DBProject.DAL;
using System.Data;


namespace DBProject
{
    public partial class ViewDoctors : System.Web.UI.Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
            // Distributed Redis-backed session via Amazon ElastiCache (EKS/ElastiCache) - replaces InProc session
            HttpContext.Current.Session["dID"] = "";
            deptDoctorInfo(sender, e);
        }

        //---------------Function Called whenever a Doctor is selected from the Grid View----//
        protected void TDoctorGrid_RowCommand(object sender, GridViewCommandEventArgs e)
        {
            if (e.CommandName == "Select")
            {
                Int16 num = Convert.ToInt16(e.CommandArgument);

                string dID = TDoctorGrid.Rows[num].Cells[2].Text;
  
                // Distributed Redis-backed session via Amazon ElastiCache (EKS/ElastiCache) - replaces InProc session
                HttpContext.Current.Session["dID"] = dID;

                Response.BufferOutput = true;
                Response.Redirect("DoctorProfile.aspx");

                return;
            }
        }



        //-----------------------Function1--------------------------//

        protected void deptDoctorInfo(object sender, EventArgs e)
        {
            myDAL objmyDAl = new myDAL();

            DataTable DT = new DataTable();

            // Distributed Redis-backed session via Amazon ElastiCache (EKS/ElastiCache) - replaces InProc session
            string deptName = (string) HttpContext.Current.Session["deptOriginal"];

            int status = objmyDAl.getDeptDoctorInfo(deptName, ref DT);


            if (status == -1)
            {
                TDoctor.Text = "There was some error in retrieving the Doctors Information.";
            }

            else
            {
                // Distributed Redis-backed session via Amazon ElastiCache (EKS/ElastiCache) - replaces InProc session
                TDoctor.Text = "Following are our Specialized Doctors of " + HttpContext.Current.Session["deptOriginal"] + " Department:";
                TDoctorGrid.DataSource = DT;
                TDoctorGrid.DataBind();
            }

            return;
        }


        //-----------------------Add a new function here------------------//
    }
}
