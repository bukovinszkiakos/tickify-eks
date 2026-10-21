using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Tickify.Migrations
{
    /// <inheritdoc />
    public partial class AddOldImageKeyToComments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "OldImageKey",
                table: "TicketComments",
                type: "nvarchar(max)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "OldImageKey",
                table: "TicketComments");
        }
    }
}
